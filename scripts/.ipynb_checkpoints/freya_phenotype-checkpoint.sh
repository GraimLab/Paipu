#!/bin/bash

## Create phenotype files for FREYA

# Current script name for error logging
script_name="freya_phenotype.sh"

# Output file for errors
error_log="error_log.txt"

# Read bioproject IDs from the file
readarray -t bioproject_array < BioProjIDs.txt
unset bioproject_array[0]

# Iterate through each bioproject
for bioproject in "${bioproject_array[@]}"; do
    # Paths to the directories
    single_dir="$bioproject/single"
    paired_dir="$bioproject/paired"

    # Check if the 'single' folder exists
    if [ -d "$single_dir" ]; then
        # Get accession numbers from single/accession.txt
        if [ -f "$single_dir/SRA_accession.txt" ]; then
            # Append 'T' to each accession separated by a comma
            awk '{print $1",T"}' "$single_dir/SRA_accession.txt" > "$single_dir/temp_phenotype.txt"

            # Append FNR (current line number) to each line in temp_phenotype; output to temp_2_phenotype
            awk -v OFS=, '{print $0, FNR}' "$single_dir/temp_phenotype.txt" > "$single_dir/temp_2_phenotype.txt"
            
            # Create phenotype.txt in the 'single' folder with header names
            echo "SampleID,Histology,Patient" > "$single_dir/phenotype.txt"
            
            # Format 'temp_2_phenotype.txt' and append it to 'phenotype.txt'
            # Output in CSV format
            awk -F, '{print $1","substr($2,1,1)","$3}' "$single_dir/temp_2_phenotype.txt" >> "$single_dir/phenotype.txt"

            # Remove temp files
            rm "$single_dir/temp_phenotype.txt" "$single_dir/temp_2_phenotype.txt"
        else
            echo -e "\nScript: $script_name Error: No SRA_accession.txt found in $single_dir" >> "$error_log"
        fi
    fi

    # Check if the 'paired' folder exists
    if [ -d "$paired_dir" ]; then
        #  # Get accession numbers from paired/accession.txt
        if [ -f "$paired_dir/SRA_accession.txt" ]; then
            # Append 'T' to each accession separated by a comma
            awk '{print $1",T"}' "$paired_dir/SRA_accession.txt" > "$paired_dir/temp_phenotype.txt"

            # Append line number to the file using FNR
            awk -v OFS=, '{print $0, FNR}' "$paired_dir/temp_phenotype.txt" > "$paired_dir/temp_2_phenotype.txt"
            
            # Create phenotype.txt in 'paired' folder with header names
            echo "SampleID,Histology,Patient" > "$paired_dir/phenotype.txt"
            
            # Format 'temp_2_phenotype.txt' and append it to 'phenotype.txt'
            # Output in CSV format
            awk -F, '{print $1","substr($2,1,1)","$3}' "$paired_dir/temp_2_phenotype.txt" >> "$paired_dir/phenotype.txt"

            # Remove temp files
            rm "$paired_dir/temp_phenotype.txt" "$paired_dir/temp_2_phenotype.txt"
        else
            # If 'accession.txt' does not exist in the 'paired' folder, print error
            echo -e "\nScript: $script_name Error: No SRA_accession.txt found in $paired_dir" >> "$error_log"
        fi
    fi
done