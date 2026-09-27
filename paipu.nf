#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
 * Paipu Pipeline
 * 
 *
 * This pipeline processes RNA-seq data across multiple species by:
 * 1. Downloading genome assemblies and annotations from NCBI
 * 2. Building genome indices (FAI, DICT, HISAT2)
 * 3. Preparing DEXSeq annotation files
 * 4. Querying NCBI SRA for metadata and harmonizing the metadata
 * 5. Preparing FREYA input files
 * 6. Downloading SRA files and converting them to FASTQs
 * 7. Running FREYA for RNA-seq processing
 * 8. Generating count matrices from DEXSeq counts 


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
 * Parse organism names from CSV
 */
def parseOrganisms(query_file) {
    def organisms = []

    // Flag to skip header
    def firstLine = true

    new File(query_file).eachLine { line ->
        if (firstLine) {
            firstLine = false
            return
        }

        // Split the current line into fields
        def fields = line.split(',')

        // Add organism names to the organisms list
        if (fields.size() > 0 && !fields[0].trim().isEmpty()) {
            organisms << fields[0].trim()
        }
    }

    return organisms
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

    input:
    tuple val(species), val(accession), val(assembly),
          path(fna),
          path(gtf)

    output:
    tuple val(species), val(accession), val(assembly),
          path("genomic.*.ht2"), emit: hisat2_index

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
    python ${params.dexseq_script} -r no ${gtf} DEXSeqGff.gff

    """
}

/*
 * Process: Retrieve and harmonize SRA metadata
 *
 * Queries the NCBI SRA using the organisms and search terms provided in
 * query_info.csv, harmonizes the retrieved metadata, and creates an
 * output directory containing one subdirectory per organism with the
 * corresponding metadata files.
 */
process SRA_METADATA_RETRIEVAL {
    // Label used in nextflow logs for each organism processed
    tag "${organism}"

    // Load the python environment
    module 'python/3.10'

    // Copy results from the task's work dir to the organism's dir created from genome prep
    publishDir {"${params.results_dir}/${organism.replace(' ', '_')}"}, mode: 'copy'

    input:
    // Get genome prep completion signal 
    val genome_prep_complete
    
    // Get current organism
    val organism

    // Input files
    path query_info
    path exclude_cols
    path retrieval_script

    // Output the organism and its metadata files
    output:
    tuple val(organism.replace(' ', '_')),
        path("${organism.replace(' ', '_')}.csv"),
        path("SRA_metadata.tsv"),
        path("bioproject_info.csv"),
        emit: metadata

    script:
    """
    # Exit if a command fails
    set -euo pipefail
    
    python3 ${retrieval_script} \
        --organism "${organism}" \
        --query-info ${query_info} \
        --exclude-cols ${exclude_cols} \
        --output-dir .
    """
}

/*
 * Process: Prepare FREYA input files
 *
 * Create the bioproject directories and input files needed
 * for downloading SRA files and running FREYA.
 */
process PREP_FREYA_INPUTS {
    // Label used in nextflow logs for each organism processed
    tag "${organism}"

    // Copy the bioproject directories from the task's work dir to the organism's dir
    publishDir {"${params.results_dir}/${organism}"}, mode: 'copy'

    input:
    tuple val(organism),
        path(sra_csv),
        path(sra_tsv),
        path(bioproject_csv),
        path(config)

    // Scripts to prep freya input
    path bin_samples_script
    path freya_phenotype_script
    path make_config_script

    // Output the organism and all of its bioproject directories
    output:
    tuple val(organism),
        path("PRJ*"), // get all bioproject directories
        emit: freya_inputs

    script:
    """
    # Exit if a command fails
    set -euo pipefail

    # binBioProjects
    # Print the bioproject (unique values) column to a new sorted file
	awk -F'\t' '
    # Find the bioproject col in the header
    NR==1 { 
        for (i=1; i<=NF; i++)
            if (tolower(\$i) == "bioproject") colIndex=i
    }
    # Print the unique bioproject ID from each row
    NR>1 {
        if (colIndex) print \$(colIndex) 
    }
    ' ${sra_tsv} | sort -u > BioProjIDs.txt

    # Run binSamples.sh to create bioproject and layout directories and SRA accession files
    bash ${bin_samples_script}

    # Create FREYA phenotype files for each bioproject layout
    bash ${freya_phenotype_script}

    # Place a config file in each bioproject layout folder with its sequencer and submitter information
    bash ${make_config_script}

    # Check if bioproject directories were created, otherwise it fails
    ls -d PRJ* > /dev/null
    """
}

/*
 * Process: Download SRA and FASTQ files
 *
 * Download SRA files and convert them to FASTQ for each bioproject.
 */
process DOWNLOAD_SRA {
    // Label used in nextflow logs for each organism and bioproject processed
    tag "${organism}_${bioproject}"

    // Load sra
    module 'sra/3.2.1'

    // Copy bioproject dir from the task's work dir to the organism's dir
    publishDir {"${params.results_dir}/${organism}"}, mode: 'copy'

    input: 
    tuple val(organism),
        val(bioproject),
        path(bioproject_dir)

    path download_sra_script

    // Output the organism, bioproject id and the downloaded bioproject dir
    output:
    tuple val(organism),
        val(bioproject),
        path(bioproject_dir),
        emit: downloaded_sra

    script:
    """
    # Exit if a command fails
    set -euo pipefail

    # Download SRA files and convert to FASTQ
    bash ${download_sra_script} ${bioproject_dir}
    """

}

/*
 * Process: Run FREYA
 *
 * Runs the FREYA pipeline for each bioproject layout.
 */
process RUN_FREYA {
    // Label used in nextflow logs for each organism and bioproject processed
    tag "${organism}_${bioproject}_${layout}"

    // Load disbatch
    module 'disbatch/2.5'

    // Copy FREYA results to the bioproject dir
    publishDir {"${params.results_dir}/${organism}/${bioproject}"}, mode: 'copy'

    input:
    tuple val(organism),
          val(bioproject),
          val(layout),
          path(layout_dir)

    path freya_single_script
    path freya_paired_script
    path master_script
    path master_paired_script

    // Output the organism, bioproject, layout and layout directory that has FREYA results
    output:
    tuple val(organism),
        val(bioproject),
        val(layout),
        path(layout_dir),
        emit: freya_results

    script:
    // Use paired FREYA scripts for paired layouts, otherwise use single FREYA scripts
    def freya_script = layout == 'paired' ? freya_paired_script : freya_single_script
    def master_freya_script = layout == 'paired' ? master_paired_script : master_script

    """
    # Exit if a command fails
    set -euo pipefail

    # Run FREYA for the current bioproject layout
    bash ${freya_script} ${layout_dir} ${master_freya_script}
    """

}

/*
 * Process: Run DESeq count matrix
 *
 * Create DESeq count matrix for each bioproject layout.
 */
process RUN_DESEQ_COUNT {
    // Label used in nextflow logs for each organism, bioproject and layout processed
    tag "${organism}_${bioproject}_${layout}"

    // Load R
    module 'R/4.5'

    input:
    tuple val(organism),
          val(bioproject),
          val(layout),
          path(layout_dir)

    path deseq_count_script
    path dexseq_r_script

    // Output the organism, bioproject, layout and layout directory that has deseq results
    output:
    tuple val(organism),
          val(bioproject),
          val(layout),
          path(layout_dir),
          emit: deseq_results

    script:
    """
    # Exit if a command fails
    set -euo pipefail

    # Run deseq count for the current bioproject layout
    bash ${deseq_count_script} ${bioproject} ${layout_dir} ${dexseq_r_script}
    """
}

/*
 * Main workflow
 */
workflow {
    log.info """
    =========================================
    Paipu Pipeline
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

    // Wait for all genome prep processes to finish
    genome_prep_complete_ch = FAI_BUILD.out.indexed_genome.mix(
        HISAT_BUILD.out.hisat2_index,
        DEXSEQ_PREPARE.out.dexseq_gff
    ).collect()

    // Create channels for SRA metadata retrieval inputs, freya prep inputs + download sra
    organism_ch = Channel.fromList(parseOrganisms(params.query_info))
    query_info_ch = Channel.value(file(params.query_info))
    exclude_cols_ch = Channel.value(file(params.exclude_cols))
    retrieval_script_ch = Channel.value(file(params.sra_retrieval_script))
    bin_samples_script_ch = Channel.value(file(params.bin_samples_script))
    freya_phenotype_script_ch = Channel.value(file(params.freya_phenotype_script))
    make_config_script_ch = Channel.value(file(params.make_config_script))
    download_sra_script_ch = Channel.value(file(params.download_sra_script))
    
    // Create channels for FREYA scripts
    freya_single_script_ch = Channel.value(file(params.freya_single_script))
    freya_paired_script_ch = Channel.value(file(params.freya_paired_script))
    master_script_ch = Channel.value(file(params.master_script))
    master_paired_script_ch = Channel.value(file(params.master_paired_script))
    
    // Create channels for dexseq scripts
    deseq_count_script_ch = Channel.value(file(params.deseq_count_script))
    dexseq_r_script_ch = Channel.value(file(params.dexseq_r_script))

    // Retrieve SRA metadata after genome prep is done
    SRA_METADATA_RETRIEVAL(
        genome_prep_complete_ch,
        organism_ch,
        query_info_ch,
        exclude_cols_ch,
        retrieval_script_ch
    )

    // Create 1 config channel for each organism's config instead of keeping everything config_frag has
    config_ch = DOWNLOAD_ASSEMBLIES.out.config_frag.map {species, accession, assembly, config ->
        tuple(species, config)
    }

    // Join each organism's metadata files with its genome config file
    freya_input_ch = SRA_METADATA_RETRIEVAL.out.metadata.join(config_ch)


    // Create and prep bioproject directories for FREYA
    PREP_FREYA_INPUTS(
        freya_input_ch,
        bin_samples_script_ch,
        freya_phenotype_script_ch,
        make_config_script_ch
    )

    // Create 1 channel for each bioproject directory from prep_freya_inputs output
    bioproject_ch = PREP_FREYA_INPUTS.out.freya_inputs.flatMap {organism, bioproject_dirs ->
        // Put the bioproject directories in a list, if it's not already a list
        def dirs = bioproject_dirs instanceof List ? bioproject_dirs : [bioproject_dirs]

        dirs.collect {bioproject_dir ->
            // Create a tuple with the organism, bioproject and bioproject file path
            tuple(organism, bioproject_dir.name, bioproject_dir)
        }
    }

    // Test download SRA and FREYA for only 1 bioproject
    // test_bioproject_ch = bioproject_ch.take(1)

    // Download SRA files and convert to FASTQ for each bioproject
    DOWNLOAD_SRA(
        bioproject_ch, // comment if testing with only 1 bioproject
        //test_bioproject_ch, // uncomment if testing with only 1 bioproject
        download_sra_script_ch
    )

    // Create 1 channel for each bioproject layout to run FREYA
    freya_layout_ch = DOWNLOAD_SRA.out.downloaded_sra.flatMap {organism, bioproject, bioproject_dir ->
        def layouts = []

        // Append 'single' and 'paired' to the bioproject dir path
        def single_dir = bioproject_dir.resolve('single')
        def paired_dir = bioproject_dir.resolve('paired')

        // If a single directory exists, add 'single' and its directory into the channel
        if (single_dir.exists()) {
            layouts << tuple(organism, bioproject, 'single', single_dir)
        }        

        // If a paired directory exists, add 'paired' and its directory into the channel
        if (paired_dir.exists()) {
            layouts << tuple(organism, bioproject, 'paired', paired_dir)
        }

        // Return the layout directories that exist
        layouts
    }

    // Run FREYA for each bioproject layout
    RUN_FREYA(
        freya_layout_ch,
        freya_single_script_ch,
        freya_paired_script_ch,
        master_script_ch,
        master_paired_script_ch
    )

    // Run DESeq count for each bioproject layout
    RUN_DESEQ_COUNT(
        RUN_FREYA.out.freya_results,
        deseq_count_script_ch,
        dexseq_r_script_ch
    )
}

