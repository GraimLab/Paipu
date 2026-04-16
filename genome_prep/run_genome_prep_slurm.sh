#!/bin/bash
#SBATCH --job-name=Paipu_Genome_Prep
#SBATCH --output=slurm_logs/paipu_%j.out
#SBATCH --error=slurm_logs/paipu_%j.err
#SBATCH --time=48:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=2GB
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=TODO_email.edu

################################################################################
# Genome Processing Pipeline
#
# This script preps given mammalian genomes for Paipu RNA-seq processing
# Queries, parses, and preps genomes with nextflow
# Designed for use on a slurm scheduler
# 
# Work directions for each nextflow job are deposited in work/
# err and out logs are deposited in slurm_logs/
################################################################################
# Exit on error 
set -e
set -u
set -o pipefail

# Configuration
# These are default parameters unless otherwise set in script.
INPUT_CSV="${INPUT_CSV:-query_output_valid.csv}"
WORK_DIR="${WORK_DIR:-work}"
LOG_DIR="${LOG_DIR:-logs}"
MASTER_DIR="${MASTER_DIR:-/orange/kgraim/panmammalian/Panmammalian/genomes/test_genomes}"

echo "========================================="
echo "Resuming Pipeline"
echo "========================================="
echo "Job ID:     ${SLURM_JOB_ID}"
echo "Start Time: $(date)"
echo "Work Dir:   ${WORK_DIR}"
echo "========================================="
echo ""

# Create directories
mkdir -p slurm_logs
mkdir -p "${LOG_DIR}"


GREEN="\033[0;32m"
CYAN="\033[0;36m"
COLOR_END="\033[0m"
RED="\033[0;31m"
step1_start=$(date +%s)
echo -e "${GREEN}Starting genome queries and downloads${COLOR_END}"
echo -e "${GREEN}Querying mammalian genomes listed in input.txt:${COLOR_END}"
sh ncbi_queries/query.sh
printf "${GREEN}COMPLETED: Genomes queried, json files for each mammal are in ncbi_queries/.${COLOR_END}"
echo -e "${GREEN}The following genomes have valid gene annotations and will be further processed:${COLOR_END}"
readarray -t valid_mammals < query_output_valid.csv
for i in ${valid_mammals[@]}; do
echo -e "${i}\n" | cut -d, -f1
done
#echo -e "${CYAN}'%s\n' ${valid_mammals[@]}${COLOR_END}"
printf "${GREEN}Valid genomes (listed above) are in output.csv to be further processed, all queried genoems are in ncbi_queries/query_output_all.csv.${COLOR_END}"
echo "Step 1 took $((step1_end - step1_start)) seconds"

# Print job information
echo "=========================================="
echo "Job started at: $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on node: $SLURM_NODELIST"
echo "Working directory: $(pwd)"
echo "=========================================="

# Load required modules
echo "Loading modules..."
module load nextflow

# Verify modules loaded
echo "Nextflow version: $(nextflow -version)"
echo "Samtools version: $(samtools --version | head -n1)"

# Create necessary directories
echo "Creating directories..."
mkdir -p logs
mkdir -p work

# Set Nextflow options
export NXF_OPTS='-Xms1g -Xmx4g'

# Run the pipeline
echo "Starting Nextflow pipeline execution"
nextflow run genome_prep.nf \
    -resume \
    -c nextflow.config \ 
    -with-report logs/report_${SLURM_JOB_ID}.html \
    -with-timeline logs/timeline_${SLURM_JOB_ID}.html \
    -with-trace logs/trace_${SLURM_JOB_ID}.txt \
    -with-dag logs/dag_${SLURM_JOB_ID}.html

# Capture exit status
EXIT_STATUS=$?
# Print completion information
echo "=========================================="
echo "Job completed at: $(date)"
echo "Exit status: $EXIT_STATUS"
echo "=========================================="
# Exit with the pipeline's exit status
exit $EXIT_STATUS
