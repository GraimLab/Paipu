#!/bin/bash

## Copy the config file with the organism's reference genome information to the organism's directory

# Store the directory's name (organism's name) without a trailing '/'
ORGANISM_NAME=$(basename "$(pwd)")
ORGANISM_NAME="${ORGANISM_NAME%/}"

# Obtain csv with organism's genome number
CSV_FILE="../../genome_prep/ncbi_queries/query_output_valid.csv"

# Find the organism in the CSV file and obtain the genome number
GENOME_NUMBER=$(awk -F',' -v org="$ORGANISM_NAME" '$1 == org {print $2 "__" $3}' "$CSV_FILE")

# Copy the config.txt file from its genome directory to the organism directory
cp "../../genome_prep/${ORGANISM_NAME}/${GENOME_NUMBER}/config.txt" .