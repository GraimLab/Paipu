#!/bin/bash

# Get the bioproject dir and library layout
project_dir="$1"

# Exit if no bioproject dir or layout were given
if [ -z "${project_dir:-}" ]; then
    echo "Error: No bioproject directory given." >&2
    exit 1
fi

# Current script name for error logging
script_name="download_sra_from_list.sh"

# Output file for errors
error_log="error_log.txt"

# Check if the project directory exists
if [ -d "$project_dir" ]; then
    # Paths to the directories
    single_dir="${project_dir}/single"
    paired_dir="${project_dir}/paired"
    
    # If the bioproject has a 'single' folder, process it:
    if [ -d "$single_dir" ] && [ -f "${single_dir}/SRA_accession.txt" ]; then
sra_file="${single_dir}/SRA_accession.txt"

        # Create SRA and FASTQ directories if they don't exist
        mkdir -p "${single_dir}/SRA"
        mkdir -p "${single_dir}/FASTQ"

        # Iterate through each line in SRA_accession.txt
        while IFS= read -r sra_id; do
            # Skip empty lines
            if [ -n "$sra_id" ]; then
                sra_dir="${single_dir}/SRA/${sra_id}"
                sra_path_sra="${sra_dir}/${sra_id}.sra"
                sra_path_sralite="${sra_dir}/${sra_id}.sralite"
                fastq_file_path="${single_dir}/FASTQ/${sra_id}.fastq.gz"

                # Remove any locked files
                if [ -f "${sra_path_sra}.lock" ]; then
                    rm -f "${sra_path_sra}.lock"
                    echo "Removed locked file: ${sra_path_sra}.lock from ${single_dir}" >> "$error_log"
                    sleep 10
                fi
                
                if [ -f "${sra_path_sralite}.lock" ]; then
                    rm -f "${sra_path_sralite}.lock"
                    echo "Removed locked file: ${sra_path_sralite}.lock from ${single_dir}" >> "$error_log"
                    sleep 10
                fi

                # Figure out which type of SRA file it is
                if [ -f "$sra_path_sra" ]; then
                    sra_file_path="$sra_path_sra"
                elif [ -f "$sra_path_sralite" ]; then
                    sra_file_path="$sra_path_sralite"
                else
                    sra_file_path=""
                fi

                # Case 1: SRA & FASTQ missing
                if [ -z "$sra_file_path" ] && [ ! -f "$fastq_file_path" ]; then
                    # SRA prefetch command to download SRA data using acc ID; store in SRA directory
                    prefetch --max-size 70G --output-directory "${single_dir}/SRA" "${sra_id}"

                    # Check which type of SRA file was downloaded
                    if [ -f "$sra_path_sra" ]; then
                        sra_file_path="$sra_path_sra"
                    elif [ -f "$sra_path_sralite" ]; then
                        sra_file_path="$sra_path_sralite"
                    fi
                    
                    # Convert SRA data to FASTQ format splitting reads into separate files; store in FASTQ directory
                    fastq-dump --gzip --skip-technical --split-3 --outdir "${single_dir}/FASTQ" "$sra_file_path"

                # Case 2: SRA exists & FASTQ missing
                elif [ -n "$sra_file_path" ] && [ ! -f "$fastq_file_path" ]; then
                    echo "FASTQ missing for $sra_id | running FASTQ dump" >> "$error_log"
                    fastq-dump --gzip --skip-technical --split-3 --outdir "${single_dir}/FASTQ" "$sra_file_path"

                # Case 3: SRA missing & FASTQ exists | both SRA and FASTQ exist
                elif [ -f "$fastq_file_path" ]; then
                    echo "Skipping $sra_id: already downloaded." >> "$error_log"
                fi
            fi
        done < "$sra_file"
        
        # Delay before removing the SRA directory
        sleep 120
    fi

    # If the bioproject has a 'paired' folder, process it:
    if [ -d "$paired_dir" ] && [ -f "${paired_dir}/SRA_accession.txt" ]; then
sra_file="${paired_dir}/SRA_accession.txt"
        
        # Create SRA and FASTQ directories if they don't exist
        mkdir -p "${paired_dir}/SRA"
        mkdir -p "${paired_dir}/FASTQ"

        # Iterate through each line in SRA_accession.txt
        while IFS= read -r sra_id; do
            # Skip empty lines
            if [ -n "$sra_id" ]; then
                sra_dir="${paired_dir}/SRA/${sra_id}"
                sra_path_sra="${sra_dir}/${sra_id}.sra"
                sra_path_sralite="${sra_dir}/${sra_id}.sralite"
                fastq_file_path_1="${paired_dir}/FASTQ/${sra_id}_1.fastq.gz"
                fastq_file_path_2="${paired_dir}/FASTQ/${sra_id}_2.fastq.gz"

                # Remove any locked files
                if [ -f "${sra_path_sra}.lock" ]; then
                    rm -f "${sra_path_sra}.lock"
                    echo "Removed locked file: ${sra_path_sra}.lock from ${paired_dir}" >> "$error_log"
                    sleep 10
                fi
                
                if [ -f "${sra_path_sralite}.lock" ]; then
                    rm -f "${sra_path_sralite}.lock"
                    echo "Removed locked file: ${sra_path_sralite}.lock from ${paired_dir}" >> "$error_log"
                    sleep 10
                fi

                # Figure out which type of SRA file it is
                if [ -f "$sra_path_sra" ]; then
                    sra_file_path="$sra_path_sra"
                elif [ -f "$sra_path_sralite" ]; then
                    sra_file_path="$sra_path_sralite"
                else
                    sra_file_path=""
                fi

                # Case 1: SRA & FASTQ missing
                if [ -z "$sra_file_path" ] && [ ! -f "$fastq_file_path_1" ] && [ ! -f "$fastq_file_path_2" ]; then
                    # SRA prefetch command to download SRA data using acc ID; store in SRA directory
                    prefetch --max-size 70G --output-directory "${paired_dir}/SRA" "${sra_id}"

                    # Check which file was downloaded
                    if [ -f "$sra_path_sra" ]; then
                        sra_file_path="$sra_path_sra"
                    elif [ -f "$sra_path_sralite" ]; then
                        sra_file_path="$sra_path_sralite"
                    fi

                    # Convert SRA data to FASTQ format splitting reads into separate files; store in FASTQ directory
                    fastq-dump --gzip --skip-technical --split-3 --outdir "${paired_dir}/FASTQ" "$sra_file_path"

                # Case 2: SRA exists & FASTQ missing
                elif [ -n "$sra_file_path" ] && { [ ! -f "$fastq_file_path_1" ] || [ ! -f "$fastq_file_path_2" ]; }; then
                    echo "FASTQs missing for $sra_id | running FASTQ dump" >> "$error_log"
                    fastq-dump --gzip --skip-technical --split-3 --outdir "${paired_dir}/FASTQ" "$sra_file_path"

                # Case 3: SRA missing & FASTQ exists | both SRA and FASTQ exist
                elif [ -f "$fastq_file_path_1" ] && [ -f "$fastq_file_path_2" ]; then
                    echo "Skipping $sra_id: already downloaded." >> "$error_log"
                fi
            fi
        done < "$sra_file"
        
        # Delay before removing the SRA directory
        sleep 120
    fi

    # Log errors if no SRA_accession.txt file found in either folder
    if { [ -d "$single_dir" ] && [ ! -f "${single_dir}/SRA_accession.txt" ] && [ ! -d "$paired_dir" ]; } || \
        { [ -d "$paired_dir" ] && [ ! -f "${paired_dir}/SRA_accession.txt" ] && [ ! -d "$single_dir" ]; }; then
        echo -e "\nScript: $script_name Error: No SRA_accession.txt found in $project_dir" >> "$error_log"
    fi
    
else
    # Exit if the bioproject directory does not exist
    echo "Error: Project directory $project_dir not found." >&2
    exit 1
fi