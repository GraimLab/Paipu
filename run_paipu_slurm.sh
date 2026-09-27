#!/bin/bash
#SBATCH --job-name=Paipu
#SBATCH --output=slurm_logs/paipu_%j.out
#SBATCH --error=slurm_logs/paipu_%j.err
#SBATCH --time=240:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=10GB
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=briasmith@ufl.edu

################################################################################
# Paipu Pipeline
#
# This script runs the Paipu workflow using Nextflow.
# The pipeline retrieves and prepares reference genomes and SRA metadata,
# downloads sequencing data, runs FREYA processing, and generates count matrices.
#
# Designed for use on a SLURM scheduler
#
# Work directions for each nextflow job are deposited in work/
# SLURM err and output logs are deposited in slurm_logs/
################################################################################

# Exit on error 
set -e
set -u
set -o pipefail

# Run from the directory where the sbatch was submitted (root pipeline directory)
cd "$SLURM_SUBMIT_DIR"

mapfile -t org_array < <( cut -d, -f1 input/query_info.csv)
delete=Organisms
array=( "${org_array[@]/$delete}" ) # delete the header that was in the file
printf '%s\n' "${array[@]}" | sed '/^$/d' > input.txt


# Configuration
# These are default parameters unless otherwise set in script.
INPUT_CSV="${INPUT_CSV:-query_output_valid.csv}"
WORK_DIR="${WORK_DIR:-work}"
LOG_DIR="${LOG_DIR:-logs}"



# Create necessary directories
echo "Creating directories..."
mkdir -p logs # Nextflow info will go here (i.e. dag.html  report.html  timeline.html  trace.txt)
mkdir -p work # Nextflow task work logs will go here
mkdir -p slurm_logs # slurm logs will go here


GREEN="\033[0;32m"
CYAN="\033[0;36m"
COLOR_END="\033[0m"
RED="\033[0;31m"
echo -e "${GREEN}Starting genome queries and downloads${COLOR_END}"
echo -e "${GREEN}Querying mammalian genomes listed in input.txt:${COLOR_END}"
sh ncbi_queries/query.sh
printf "${GREEN}COMPLETED: Genomes queried, json files for each mammal are in ncbi_queries/.${COLOR_END}"
echo -e "${GREEN}The following genomes have valid gene annotations and will be further processed:${COLOR_END}"
readarray -t valid_mammals < query_output_valid.csv
for i in ${valid_mammals[@]}; do
echo -e "${i}\n" | cut -d, -f1
done

printf "${GREEN}Valid genomes (listed above) are in query_output_valid.csv to be further processed, all queried genomes are in ncbi_queries/query_output_all.csv.${COLOR_END}"

# Print job information
echo "=========================================="
echo "Job started at: $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on node: $SLURM_NODELIST"
echo "Working directory: $(pwd)"
echo "=========================================="

# Load required modules
echo "Loading modules..."
module load nextflow/26.04.3

# Verify modules loaded
echo "Nextflow version: $(nextflow -version)"

# Set Entrez credentials for SRA metadata retrieval
# export ENTREZ_EMAIL="TODOyour_email"
# export ENTREZ_API_KEY="TODOyour_api_key"
export ENTREZ_EMAIL="briasmith@ufl.edu"
export ENTREZ_API_KEY="0a6d6d89e63f66a9b1e2fe053d919d93fa09"

# Set Nextflow options
export NXF_OPTS='-Xms1g -Xmx4g' # setting memory sizes

# Run the pipeline
echo "Starting Nextflow pipeline execution"
nextflow run paipu.nf \
    -resume \
    -c nextflow.config

# Capture exit status
EXIT_STATUS=$?
# Print completion information
echo "=========================================="
echo "Job completed at: $(date)"
echo "Exit status: $EXIT_STATUS"
echo "=========================================="
# Exit with the pipeline's exit status
exit $EXIT_STATUS
