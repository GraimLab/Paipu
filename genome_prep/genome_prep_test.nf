#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
 * Genome Processing Pipeline
 * Converted from Snakemake to Nextflow DSL2
 *
 * This pipeline processes multiple species genomes by:
 * 1. Downloading genome assemblies and annotations from NCBI
 * 2. Building genome indices (FAI, DICT, HISAT2)
 * 3. Preparing DEXSeq annotation files
 * Run time ~ 24 min per mammal
 */


/*
 * Parse CSV and create input channel
 */
def parseInputCSV(csv_file) {
    def records = []

    new File(csv_file).eachLine { line ->
        def fields = line.split(',')
        if (fields.size() > 0 && line.trim()) {
            // CSV format: 0:Species, 1:Accession, 2:Assembly
            records << [
                species: fields[0].trim(),
                accession: fields[1].trim(),
                assembly: fields[2].trim()
            ]
        }
    }

    return records
}

/*
 * Process: Download genome assemblies from NCBI
 *
 * Emits the genome files AND a base config fragment containing the header
 * plus the genome-file line. Downstream processes each emit their own
 * fragment; all fragments are concatenated at the end.
 */
process DOWNLOAD_ASSEMBLIES {
    tag "${species}_${accession}_${assembly}"

    module 'ncbi_cli'

    publishDir {"${params.results_dir}/${species}/${accession}__${assembly}"}, mode: 'copy'

    input:
    tuple val(species), val(accession), val(assembly)

    output:
    tuple val(species), val(accession), val(assembly),
          path("genomic.fna"),
          path("genomic.gtf"), emit: genome_files
    tuple val(species), val(accession), val(assembly),
          path("config.txt"), emit: config_frag

    script:
    def complete_path = "${species}/${accession}__${assembly}"
    """
    set -o xtrace
    echo ${accession}
    # Download genome and GTF from NCBI
    datasets download genome accession ${accession} \\
        --include genome,gtf \\
        --filename ${accession}.zip

    # Extract files
    unzip ${accession}.zip

    # Move files to expected locations
    mv ncbi_dataset/data/${accession}/*.fna genomic.fna
    mv ncbi_dataset/data/${accession}/genomic.gtf genomic.gtf
    chmod g+r *
    # Cleanup
    rm -r ncbi_dataset
    rm ${accession}.zip
    rm -f README.md

    # Create base config fragment (ordered prefix keeps concat order stable)
    echo "#FREYA PIPELINE CONFIG FOR ${species} ${accession} ${assembly} CREATED ON \$(date)" > config.txt
    echo "" >> config.txt
    echo "hisat2_version=2.2.1" >> config.txt
    echo "fastqc_version=0.11.7" >> config.txt
    echo "dexcount_version=1.42.0" >> config.txt
    echo "picard_version=2.25.5" >> config.txt
    echo "gatk_version=4.4.0.0" >> config.txt
    echo "snpeff_version=5.0" >> config.txt
    echo "samtools_version=1.15" >> config.txt
    echo "" >> config.txt
    echo "#GENOME FILE: (must also have associated fai file)" >> config.txt
    echo "CFFA=${params.results_dir}/${complete_path}/genomic.fna" >> config.txt
    echo "#HISAT2 FILES:" >> config.txt
    echo "HSX=${params.results_dir}/${complete_path}/hisat2/genomic" >> config.txt

    echo "#DEXSEQ ANNOTATION GFF FILE:" >> config.txt
    echo "DC_GFF=${params.results_dir}/${complete_path}/DEXSeqGff.gff" >> config.txt
    """
}

/*
 * Process: Build FAI index and sequence dictionary
 */
process FAI_BUILD {
    tag "${species}_${accession}_${assembly}"
    module 'samtools:picard'

    publishDir {"${params.results_dir}/${species}/${accession}__${assembly}"}, mode: 'copy'

    input:
    tuple val(species), val(accession), val(assembly),
          path(fna),
          path(gtf)

    output:
    tuple val(species), val(accession), val(assembly),
          path("${fna}.fai"),
          path("genomic.dict"), emit: indexed_genome

    script:
    """
    # Create FAI index
    samtools faidx ${fna}

    # Create sequence dictionary
    picard -Xmx50g CreateSequenceDictionary R=${fna}
    """
}

/*
 * Process: Build HISAT2 index
 *
 * Data outputs go to the hisat2/ subdir. Config fragment is emitted
 * separately for final assembly (NOT published here).
 */
process HISAT_BUILD {
    tag "${species}_${accession}_${assembly}"

    module 'hisat2/2.2.1'

    publishDir {"${params.results_dir}/${species}/${accession}__${assembly}/hisat2"}, mode: 'copy', pattern: '*.ht2'
    //publishDir {"${params.results_dir}/${species}/${accession}__${assembly}"}, mode: 'copy', pattern: 'config_10_hisat.txt'

    input:
    tuple val(species), val(accession), val(assembly),
          path(fna),
          path(gtf)

    output:
    tuple val(species), val(accession), val(assembly),
          path("genomic.*.ht2"), emit: hisat2_index
    //tuple val(species), val(accession), val(assembly),
    //      path("config_10_hisat.txt"), emit: config_frag

    script:
    def target_name = "genomic"
    """
    # Build HISAT2 index
    hisat2-build ${fna} ${target_name}
    """
}

/*
 * Process: Prepare DEXSeq annotation
 */
process DEXSEQ_PREPARE {
    tag "${species}_${accession}_${assembly}"

    module 'htseq/2.0.3'

    publishDir {"${params.results_dir}/${species}/${accession}__${assembly}"}, mode: 'copy'

    input:
    tuple val(species), val(accession), val(assembly),
        path(fna),
        path(gtf)

    output:
    tuple val(species), val(accession), val(assembly),
          path("DEXSeqGff.gff"), emit: dexseq_gff
    // tuple val(species), val(accession), val(assembly),
    //       path("config_20_dexseq.txt"), emit: config_frag

    script:
    """
    # Prepare DEXSeq annotation
    python ${projectDir}/${params.dexseq_script} -r no ${gtf} DEXSeqGff.gff

    """
}



/*
 * Main workflow
 */
workflow {
    log.info """
    =========================================
    Genome Processing Pipeline
    =========================================
    Input CSV      : ${params.input_csv}
    Log directory  : ${params.log_dir}
    Results directory : ${params.results_dir}
    =========================================
    """

    // Parse input CSV and create channel
    input_records = Channel.fromList(parseInputCSV(params.input_csv))

    // Create tuples from parsed records
    input_ch = input_records.map { record ->
        tuple(record.species, record.accession, record.assembly)
    }

    // Download assemblies
    DOWNLOAD_ASSEMBLIES(input_ch)

    // Build indices in parallel
    FAI_BUILD(DOWNLOAD_ASSEMBLIES.out.genome_files)
    HISAT_BUILD(DOWNLOAD_ASSEMBLIES.out.genome_files)
    DEXSEQ_PREPARE(DOWNLOAD_ASSEMBLIES.out.genome_files)

    

   
}



