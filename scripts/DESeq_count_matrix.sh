#!/bin/bash

#module load R

DATASET=$1
# MAMMAL=$2
# LAYOUT=$3
LAYOUT_DIR=$2
DEXSEQ_SCRIPT=$3

# PIPELINE_DIR exported from run_deseq_count.sh

# Set path to DEXSeq R script
#DEXSEQ_SCRIPT="${PIPELINE_DIR}/scripts/DEXSeq.R"

#Rscript "${DEXSEQ_SCRIPT}" -d "${DATASET}" -m "${MAMMAL}" -l "${LAYOUT}" -i "${LAYOUT_DIR}"
Rscript "${DEXSEQ_SCRIPT}" -d "${DATASET}" -i "${LAYOUT_DIR}"
