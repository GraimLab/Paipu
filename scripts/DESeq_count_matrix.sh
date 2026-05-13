#!/bin/sh
#SBATCH --job-name=DEXSeqCountMatrix
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem-per-cpu=100gb
#SBATCH --time=5:00:00

module load R

DATASET=$1
MAMMAL=$2
LAYOUT=$3

# PIPELINE_DIR exported from run_deseq_count.sh

# Set path to DEXSeq R script
DEXSEQ_SCRIPT="${PIPELINE_DIR}/scripts/DEXSeq.R"

Rscript "${DEXSEQ_SCRIPT}" -d "${DATASET}" -m "${MAMMAL}" -l "${LAYOUT}"
