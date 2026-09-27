#!/bin/bash

DATASET_DIR=$1
MASTER_SCRIPT=$2

# Load modules 
#ml disbatch/2.5
export PYTHONPATH=/apps/disbatch/2.5/disBatch

# Clear inherited SLURM CPU binding so DisBatch can manage its own job steps
unset SLURM_CPU_BIND
unset SLURM_CPU_BIND_VERBOSE
unset SLURM_CPU_BIND_LIST
unset SLURM_CPU_BIND_TYPE

# Run FREYA
bash "$MASTER_SCRIPT" \
    "${DATASET_DIR}/config.txt" \
    "${DATASET_DIR}/phenotype.txt" \
    "${DATASET_DIR}/FASTQ" \
    "$SLURM_JOB_ID" \
    "${DATASET_DIR}/freya_results" \
    hisat2 fastqc dexcount aorrg markdup splitncr