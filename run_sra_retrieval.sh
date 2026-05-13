#!/bin/bash
#SBATCH --job-name=sra_retrieval
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem=50gb
#SBATCH --time=24:00:00
#SBATCH --output=logs/%j_sra_retrieval.log # Standard output log

# Load the python module
module load python/3.10

# Set Entrez credentials
export ENTREZ_EMAIL=""
export ENTREZ_API_KEY=""

# Run the SRA retrieval script
python3 sra_metadata_retrieval.py