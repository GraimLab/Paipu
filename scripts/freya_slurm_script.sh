#!/bin/bash
#SBATCH --job-name=SINGLE_disBatch
#SBATCH --nodes=6
#SBATCH --ntasks=6
#SBATCH --cpus-per-task=4
#SBATCH --mem=50gb
#SBATCH --time=240:00:00
#SBATCH --output=%j_freya_slurm_script.log

# Get input args from command line
DATASET=$1
MAMMAL=$2
LAYOUT=$3

# Load modules 
ml disbatch/2.5
export PYTHONPATH=/apps/disbatch/2.5/disBatch

# PIPELINE_DIR was exported from run_freya.sh

# Set master script path
MASTER_SCRIPT="${PIPELINE_DIR}/scripts/master_script.sh"

# Set dataset directory path
DATASET_DIR="${PIPELINE_DIR}/output/${MAMMAL}/${DATASET}/${LAYOUT}"

# Set FREYA logs path
FREYA_LOG_DIR="${PIPELINE_DIR}/output/${MAMMAL}/freya_logs"

# Change to FREYA log directory before running master_script so its logs can go in there
cd "$FREYA_LOG_DIR" || exit 1

# Run FREYA
bash "$MASTER_SCRIPT" \
    "${DATASET_DIR}/config.txt" \
    "${DATASET_DIR}/phenotype.txt" \
    "${DATASET_DIR}/FASTQ" \
    "$SLURM_JOB_ID" \
    "${DATASET_DIR}/freya_results" \
    hisat2 fastqc dexcount aorrg markdup splitncr