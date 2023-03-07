import groovy.json.JsonBuilder


process callCNV {
    label "wf_cnv"
    cpus 1
    publishDir "${params.out_dir}/qdna_seq", mode: 'copy', pattern: "*"
    input:
        tuple path(bam), path(bai)
        val(genome_build)
    output:
        tuple path("${params.sample_name}_combined.bed"), path("${params.sample_name}*"), path("${params.sample_name}_noise_plot.png"), path("${params.sample_name}_isobar_plot.png")

    script:
        """
        run_qdnaseq.r --bam ${bam} --out_prefix ${params.sample_name} --binsize ${params.bin_size} --reference ${genome_build}
        cut -f5 ${params.sample_name}_calls.bed | paste ${params.sample_name}_bins.bed - > ${params.sample_name}_combined.bed
        check=`awk -F "\t" 'NF != 6' ${params.sample_name}_segs.seg`
    
        if [ -n "\${check}" ]; then \
            echo "vcf is malformed"; \
            workflow-glue fix_vcf --vcf ${params.sample_name}_calls.vcf --fixed_vcf ${params.sample_name}_calls_fixed.vcf --sample_id ${params.sample_name}; \
            workflow-glue fix_vcf --vcf ${params.sample_name}_segs.vcf --fixed_vcf ${params.sample_name}_segs_fixed.vcf --sample_id ${params.sample_name}; \

            rm ${params.sample_name}_calls.vcf
            mv ${params.sample_name}_calls_fixed.vcf ${params.sample_name}_calls.vcf
            rm ${params.sample_name}_segs.vcf
            mv ${params.sample_name}_segs_fixed.vcf ${params.sample_name}_segs.vcf
        fi
        """
}

process getVersions {
    label "wf_cnv"
    cpus 1
    output:
        path "versions.txt"
    script:
        """
        python -c "import pysam; print(f'pysam,{pysam.__version__}')" >> versions.txt
        R --version | grep -w R | grep version | cut -f3 -d" " | sed 's/^/R,/' >> versions.txt
        R --slave -e 'packageVersion("QDNAseq")' | cut -d\\' -f2 | sed 's/^/QDNAseq,/' >> versions.txt
        samtools --version | head -n 1 | sed 's/ /,/' >> versions.txt
        """
}


process getParams {
    label "wf_cnv"
    cpus 1
    output:
        path "params.json"
    script:
        def paramsJSON = new JsonBuilder(params).toPrettyString()
        """
        # Output nextflow params object to JSON
        echo '$paramsJSON' > params.json
        """
}


process makeReport {
    label "wf_cnv"
    cpus 1
    input:
        path(read_stats)
        tuple path(cnv_calls), val(cnv_files), path(noise_plot), path(isobar_plot)
        path "versions/*"
        path "params.json"
        val(genome_build)
    output:
        path("*wf-human-cnv-report.html")

    script:
        def report_name = "${params.sample_name}.wf-human-cnv-report.html"
        """
        workflow-glue cnv_plot \
            -q ${cnv_calls} \
            -o $report_name \
            --read_stats ${read_stats}\
            --params params.json \
            --versions versions \
            --bin_size ${params.bin_size} \
            --genome ${genome_build} \
            --sample_id ${params.sample_name} \
            --noise_plot ${noise_plot} \
            --isobar_plot ${isobar_plot}
        """

}

// See https://github.com/nextflow-io/nextflow/issues/1636
// This is the only way to publish files from a workflow whilst
// decoupling the publish from the process steps.
process output_cnv {
    // publish inputs to output directory
    label "wf_cnv"
    publishDir "${params.out_dir}", mode: 'copy', pattern: "*"
    input:
        path fname
    output:
        path fname
    """
    echo "Writing output files"
    """
}


