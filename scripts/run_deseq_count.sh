#!/bin/bash
#SBATCH --job-name=run_deseq_count	
#SBATCH --nodes=4                   	
#SBATCH --ntasks=4                 		
#SBATCH --cpus-per-task=1
#SBATCH --mem=5gb
#SBATCH --time=5:00:00

# Assuming the files needed are in the current directory
PROJ_ID_FILE="BioProjIDs.txt"

# PIPELINE_DIR and ORGANISM_DIR was exported from run_freya.sh
# Store the current directory path and organism directory name
ORIGINAL_DIR="${PIPELINE_DIR}/output/${ORGANISM_DIR}"

# Set directory with pipeline scripts
SCRIPT_DIR="${PIPELINE_DIR}/scripts"

# Assign the DESeq_count_matrix script path to a variable
DESEQ_SCRIPT="${SCRIPT_DIR}/DESeq_count_matrix.sh"

# Current script name for error logging
SCRIPT_NAME="run_deseq_count.sh"

# Output file for errors
ERROR_LOG="${ORIGINAL_DIR}/error_log.txt"

# Check if PROJ_ID_FILE doesn't exist, then exit
if [ ! -f "$PROJ_ID_FILE" ]; then
    echo -e "\nBioProject IDs file not found." >> "$ERROR_LOG"
    exit 1
fi

# Iterate through each bioproject ID starting from the second line of the BioProjIDs file
for BioProjectID in $(tail -n +2 "$PROJ_ID_FILE"); do
    # Check if the bioproject has a single/paired/both folders
    single_dir="${ORIGINAL_DIR}/${BioProjectID}/single"
    paired_dir="${ORIGINAL_DIR}/${BioProjectID}/paired"

    # Check if at least one of the directories exist
    if [ -d "$single_dir" ] || [ -d "$paired_dir" ]; then
        # Change to slurm script directory before running it
        cd "$SCRIPT_DIR"  || { echo -e "\nScript: $SCRIPT_NAME Error: Directory change to slurm script dir failed." >> "$ERROR_LOG"; exit 1; }
    
        # If the single directory exists:
        if [ -d "$single_dir" ]; then
            job_id=$(
                sbatch \
                    --export=ALL,PIPELINE_DIR="$PIPELINE_DIR",ORGANISM_DIR="$ORGANISM_DIR" \
                    "$DESEQ_SCRIPT" "$BioProjectID" "$ORGANISM_DIR" "single" \
                | awk '{print $4}') # the 4th field of 'Submitted batch job 1232' is the job id
            
            # Log the job ID
            echo -e "\nScript: $SCRIPT_NAME Log: Run submitted for $BioProjectID (Single) Job ID: $job_id" >> "$ERROR_LOG"
        fi
        
        # If the paired directory exists:
        if [ -d "$paired_dir" ]; then
            job_id=$(
                sbatch \
                    --export=ALL,PIPELINE_DIR="$PIPELINE_DIR",ORGANISM_DIR="$ORGANISM_DIR" \
                    "$DESEQ_SCRIPT" "$BioProjectID" "$ORGANISM_DIR" "paired" \
                | awk '{print $4}') # the 4th field of 'Submitted batch job 1232' is the job id

            # Log the job ID
            echo -e "\nScript: $SCRIPT_NAME Log: Run submitted for $BioProjectID (Paired) Job ID: $job_id" >> "$ERROR_LOG"
        fi

    else
        # Log the error to the error log file if there's no library layout / there's an unknown layout
        echo -e "\nScript: $SCRIPT_NAME Error: Neither 'single' nor 'paired' directory exists for BioProject: $BioProjectID in $ORIGINAL_DIR" >> "$ERROR_LOG"
        exit 1
    fi

    # Change back to original directory
    cd "$ORIGINAL_DIR" || { echo -e "\nScript: $SCRIPT_NAME Error: Directory change to original dir failed." >> "$ERROR_LOG"; exit 1; }

    sleep 10

done