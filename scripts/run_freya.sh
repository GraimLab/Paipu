#!/bin/bash
#SBATCH --job-name=run_freya	
#SBATCH --nodes=4                   	
#SBATCH --ntasks=4                		
#SBATCH --cpus-per-task=3
#SBATCH --mem=50gb
#SBATCH --time=10:00:00
#SBATCH --output=run_freya_%j.log

# Assuming the BioProj ID file is in the current directory
PROJ_ID_FILE="BioProjIDs.txt"

# Store the current organism directory
ORIGINAL_DIR=$(pwd)

# Get pipeline root directory - 2 levels up from the organism folder
PIPELINE_DIR=$(cd "$ORIGINAL_DIR/../.." && pwd)

# Set directory with pipeline scripts
SCRIPT_DIR="${PIPELINE_DIR}/scripts"

# Assign freya single and paired script file paths to variables
SINGLE_SCRIPT="${SCRIPT_DIR}/freya_slurm_script.sh"
PAIRED_SCRIPT="${SCRIPT_DIR}/freya_slurm_script_paired.sh"

# Organism's directory name
ORGANISM_DIR=$(basename "$(pwd)")

FREYA_LOG_DIR="${ORIGINAL_DIR}/freya_logs"

# Current script name for error logging
SCRIPT_NAME="run_freya.sh"

# Store all job IDs for dependencies
all_job_ids=""

# Output file for errors
ERROR_LOG="${ORIGINAL_DIR}/error_log.txt"

# Output file to store submitted job IDs for slurm dependency
JOB_ID_LOG="${ORIGINAL_DIR}/freya_submitted_jobs.txt"

# Check if PROJ_ID_FILE doesn't exist, then exit
if [ ! -f "$PROJ_ID_FILE" ]; then
    echo -e "\nBioProject IDs file not found." >> "$ERROR_LOG"
    exit 1
fi

# Iterate through each BioProjectID starting from the second line of the BioProjIDs file
for BioProjectID in $(tail -n +2 "$PROJ_ID_FILE"); do
    # Check if the bioproject has a single/paired/both folders
    single_dir="${ORIGINAL_DIR}/${BioProjectID}/single"
    paired_dir="${ORIGINAL_DIR}/${BioProjectID}/paired"

    # Check if at least one of the directories exist
    if [ -d "$single_dir" ] || [ -d "$paired_dir" ]; then
        # Change to the freya slurm script directory before running it
        cd "$SCRIPT_DIR"  || { echo -e "\nScript: $SCRIPT_NAME Error: Directory change to slurm script dir failed." >> "$ERROR_LOG"; exit 1; }
    
        # If the single directory exists:
        if [ -d "$single_dir" ]; then
            single_job_id=$(
                sbatch \
                    --export=ALL,PIPELINE_DIR="$PIPELINE_DIR" \
                    --output="${FREYA_LOG_DIR}/single_${BioProjectID}_%j.log" \
                    "$SINGLE_SCRIPT" "$BioProjectID" "$ORGANISM_DIR" "single" \
                | awk '{print $4}') # the 4th field of 'Submitted batch job 1232' is the job id
            
            # Store job ID for the dependency string
            all_job_ids="${all_job_ids}${single_job_id}:" 
            
            # Log the job ID to its log file for slurm dependency
            echo "$single_job_id" >> "$JOB_ID_LOG"
            
            # Log the job ID with its BioProject name
            echo -e "\nScript: $SCRIPT_NAME Log: Run submitted for $BioProjectID (Single) Job ID: $single_job_id" >> "$ERROR_LOG"
        fi
        
        # If the paired directory exists:
        if [ -d "$paired_dir" ]; then
            paired_job_id=$(
                sbatch \
                    --export=ALL,PIPELINE_DIR="$PIPELINE_DIR" \
                    --output="${FREYA_LOG_DIR}/paired_${BioProjectID}_%j.log" \
                    "$PAIRED_SCRIPT" "$BioProjectID" "$ORGANISM_DIR" "paired" \
                | awk '{print $4}') # the 4th field of 'Submitted batch job 1232' is the job id
            
            # Store job ID for the dependency string
            all_job_ids="${all_job_ids}${paired_job_id}:" 
            
            # Log the job ID to its log file for sbatch dependency
            echo "$paired_job_id" >> "$JOB_ID_LOG"
            
            # Log the job ID with its BioProject name
            echo -e "\nScript: $SCRIPT_NAME Log: Run submitted for $BioProjectID (Paired) Job ID: $paired_job_id" >> "$ERROR_LOG"
        fi

    else
        # Log the error to the error log file if there's no library layout / there's an unknown layout
        echo -e "\nScript: $SCRIPT_NAME Error: Neither 'single' nor 'paired' directory exists for BioProject: $BioProjectID in $ORIGINAL_DIR" >> "$ERROR_LOG"
    fi

    # Change back to original directory
    cd "$ORIGINAL_DIR" || { echo -e "\nScript: $SCRIPT_NAME Error: Directory change to original dir failed." >> "$ERROR_LOG"; exit 1; }
    sleep 10
done

# Remove the last colon from all_job_ids
all_job_ids="${all_job_ids%:}"

# Submit run_deseq_count.sh with dependencies on all jobs created by run_freya.sh
if [ -n "$all_job_ids" ]; then
    echo "Submitting run_deseq_count.sh with dependencies on the following job IDs: $all_job_ids" >> "$ERROR_LOG"
    sbatch \
        --dependency=afterok:$all_job_ids \
        --export=ALL,PIPELINE_DIR="$PIPELINE_DIR",ORGANISM_DIR="$ORGANISM_DIR" \
        run_deseq_count.sh
else
    echo "Error: No job IDs were saved in run_freya.sh for run_deseq_count.sh dependency run." >> "$ERROR_LOG"
    exit 1
fi