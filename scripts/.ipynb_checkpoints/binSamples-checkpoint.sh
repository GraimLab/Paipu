#!/bin/bash

## Create SRA_accession.txt files in each bioproject singe/paired folder

# Read the BioProjIDs.txt file into an array
readarray -t bioproject_array < BioProjIDs.txt

# Iterate over each element in the array
for i in "${bioproject_array[@]}"; do
    # Create a directory with the bioproject name
    mkdir "$i"
done
 
# Assuming the file is in the current directory
proj_info_csv="bioproject_info.csv"

# Create temporary files for single and paired layouts
temp_single="single_layouts.txt"
temp_paired="paired_layouts.txt"

# Get column indices from header
header=$(head -n 1 "$proj_info_csv")
bioproject_col=$(echo "$header" | tr ',' '\n' | grep -n -i 'bioproject' | cut -d: -f1)
layout_col=$(echo "$header" | tr ',' '\n' | grep -n -i 'library_layout' | cut -d: -f1)
run_acc_col=$(echo "$header" | tr ',' '\n' | grep -n -i 'run_accession' | cut -d: -f1)

# Get bioprojects with single layouts and store in temp file
awk -F, -v bioproject_column="$bioproject_col" -v layout_column="$layout_col" '
BEGIN { OFS="," }
NR > 1 { 
    if (tolower($layout_column) == "single") {
        print $bioproject_column
    }
}' "$proj_info_csv" | sort | uniq > "$temp_single"

# Get bioprojects with paired layouts and store in temp file
awk -F, -v bioproject_column="$bioproject_col" -v layout_column="$layout_col" '
BEGIN { OFS="," }
NR > 1 { 
    if (tolower($layout_column) == "paired") {
        print $bioproject_column
    }
}' "$proj_info_csv" | sort | uniq > "$temp_paired"

# Iterate through each bioproject to create the necessary folders
# Find bioprojects that are present in both single and paired layout lists
comm -12 "$temp_single" "$temp_paired" | while read bioproject; do
    mkdir -p "$bioproject/single" "$bioproject/paired"
    
    # Obtain accession numbers for single bioprojects and save in a txt file  
    awk -F',' -v bp="$bioproject" -v acc_col="$run_acc_col" -v bp_col="$bioproject_col" -v layout_column="$layout_col" \
    'NR>1 && $bp_col == bp && tolower($layout_column) == "single" {print $acc_col}' \
    "$proj_info_csv" > "$bioproject/single/SRA_accession.txt"
    
    # Obtain accession numbers for paired bioprojects and save in a txt file
    awk -F',' -v bp="$bioproject" -v acc_col="$run_acc_col" -v bp_col="$bioproject_col" -v layout_column="$layout_col" \
    'NR>1 && $bp_col == bp && tolower($layout_column) == "paired" {print $acc_col}' \
    "$proj_info_csv" > "$bioproject/paired/SRA_accession.txt"
done

# Find bioprojects that are in single but not in paired
comm -23 "$temp_single" "$temp_paired" | while read bioproject; do
    mkdir -p "$bioproject/single"
    
    # Obtain accession numbers for single bioprojects and save in a txt file
    awk -F',' -v bp="$bioproject" -v acc_col="$run_acc_col" -v bp_col="$bioproject_col" -v layout_column="$layout_col" \
    'NR>1 && $bp_col == bp && tolower($layout_column) == "single" {print $acc_col}' \
    "$proj_info_csv" > "$bioproject/single/SRA_accession.txt"
done

# Find bioprojects that are in paired but not in single
comm -13 "$temp_single" "$temp_paired" | while read bioproject; do
    mkdir -p "$bioproject/paired"
    
    # Obtain accession numbers for paired bioprojects and save in a txt file
    awk -F',' -v bp="$bioproject" -v acc_col="$run_acc_col" -v bp_col="$bioproject_col" -v layout_column="$layout_col" \
    'NR>1 && $bp_col == bp && tolower($layout_column) == "paired" {print $acc_col}' \
    "$proj_info_csv" > "$bioproject/paired/SRA_accession.txt"
done

# Remove temp files
rm "$temp_single" "$temp_paired"