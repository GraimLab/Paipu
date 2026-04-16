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


// Print pipeline information
log.info """
=========================================
Genome Processing Pipeline
=========================================
Input CSV      : ${params.input_csv}
Log directory  : ${params.log_dir}
Master dir     : ${params.master_dir}
=========================================
"""

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
 */
process DOWNLOAD_ASSEMBLIES {
    tag "${species}_${accession}_${assembly}"
    
    module 'ncbi_cli'
    
    publishDir "${species}/${accession}__${assembly}", mode: 'copy'
    
    input:
    tuple val(species), val(accession), val(assembly)
    
    output:
    tuple val(species), val(accession), val(assembly), 
          path("genomic.fna"), 
          path("genomic.gtf"), 
          path("config.txt"), emit: genome_files
    
    script:
    def complete_path = "${species}/${accession}__${assembly}"
    """
    set -o xtrace
    echo ${accession}
    # Download genome and GTF from NCBI
    datasets download genome accession ${accession} \
        --include genome,gtf \
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
    
    # Create config file
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
    echo "CFFA=${params.master_dir}/${complete_path}/genomic.fna" >> config.txt
    """
}

/*
 * Process: Build FAI index and sequence dictionary
 */
process FAI_BUILD {
    tag "${species}_${accession}_${assembly}"
    module 'samtools:picard'
    
    publishDir "${species}/${accession}__${assembly}", mode: 'move'
    
    input:
    tuple val(species), val(accession), val(assembly), 
          path(fna),
          path(gtf),
          path(config)
    
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

// /*
//  * Process: Build HISAT2 index
//  */
process HISAT_BUILD {
    tag "${species}_${accession}_${assembly}"
    
    module 'hisat2/2.2.1'
    
    publishDir "${species}/${accession}__${assembly}/hisat2", mode: 'move'
    
    input:
    tuple val(species), val(accession), val(assembly), 
          path(fna), 
          path(gtf), 
          path(config)
          
    
    output:
    tuple val(species), val(accession), val(assembly), 
          path("genomic.*.ht2"), emit: hisat2_index
          path("config.txt"), emit: config_update

     
    
    script:
    def target_name = "genomic"
    """
    # Build HISAT2 index
    hisat2-build ${fna} ${target_name}

    echo "#HISAT2 FILES:" >> config.txt
    echo "HSX=${params.master_dir}/${species}/${accession}__${assembly}/hisat2/genomic" >> config.txt
    """
 }

// /*
//  * Process: Prepare DEXSeq annotation
//  */
process DEXSEQ_PREPARE {
    tag "${species}_${accession}_${assembly}"
    
    module 'htseq/2.0.3'
    
    publishDir "${species}/${accession}__${assembly}", mode: 'move'
    
    input:
    tuple val(species), val(accession), val(assembly), 
        path(fna),
        path(gtf),
        path(config)
    
    output:
    tuple val(species), val(accession), val(assembly), path("DEXSeqGff.gff"), emit: dexseq_gff
    path("config.txt"), emit: config_update
    
    script:
    """
    # Prepare DEXSeq annotation
    python ${params.dexseq_script} -r no ${gtf} DEXSeqGff.gff
    
    # Update config file

    echo "#DEXSEQ ANNOTATION GFF FILE:" >> config.txt
    echo "DC_GFF=${params.master_dir}/${species}/${accession}__${assembly}/DEXSeqGff.gff" >> config.txt
    """
}

/*
 * Main workflow
 */
workflow {
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
    
    // Summary
    DOWNLOAD_ASSEMBLIES.out.genome_files
        .subscribe { species, accession, assembly, fna, gtf, config ->
            log.info "Processed: ${species} (${accession}__${assembly})"
        }
}

workflow.onComplete {
    log.info """
    =========================================
    Pipeline completed!
    Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration  : ${workflow.duration}
    =========================================
    """
}
