#!/bin/bash

## Place a config file in each bioproject layout folder with its sequencer and submitter information

# Assuming bioproject_info.csv is in the current directory
PROJ_INFO_CSV="bioproject_info.csv"

# Keep track of the state of each BioProject
current_bioproject=""

# Loop through each row in the CSV file
tail -n +2 "$PROJ_INFO_CSV" | while IFS=, read -r BioProject Accession Layout Instrument Organization; do
    BioProjectDir="$BioProject"
    
    # Set "NA" for empty Instrument or Organization
    Instrument="${Instrument:-NA}"
    Organization="${Organization:-NA}"
    
    # Clear flags for each BioProject to be processed
    if [ "$BioProject" != "$current_bioproject" ]; then
        processed_single=""
        processed_paired=""
        current_bioproject="$BioProject"
    fi

    # Check if the BioProject directory exists
    if [ -d "$BioProjectDir" ]; then
        # Process single layout
        if [[ "$Layout" == "SINGLE" && -d "$BioProjectDir/single" && -z "$processed_single" ]]; then
            # Copy config.txt file to the BioProject single directory
            cp "config.txt" "$BioProjectDir/single/"
            
            # Append sequencer & submitter to the config file
            echo "RGPLParam=\"$(echo "$Instrument" | sed 's/ //g' | tr '[:lower:]' '[:upper:]')\"" >> "$BioProjectDir/single/config.txt"
            echo "RGPUParam=\"$(echo "$Organization" | sed 's/ //g' | tr '[:lower:]' '[:upper:]')\"" >> "$BioProjectDir/single/config.txt"
            processed_single="1"  # single has been processed
        fi

        # Process paired layout
        if [[ "$Layout" == "PAIRED" && -d "$BioProjectDir/paired" && -z "$processed_paired" ]]; then
            # Copy config.txt file to the BioProject paired directory
            cp "config.txt" "$BioProjectDir/paired/"
            
            # Append sequencer & submitter to the config file
            echo "RGPLParam=\"$(echo "$Instrument" | sed 's/ //g' | tr '[:lower:]' '[:upper:]')\"" >> "$BioProjectDir/paired/config.txt"
            echo "RGPUParam=\"$(echo "$Organization" | sed 's/ //g' | tr '[:lower:]' '[:upper:]')\"" >> "$BioProjectDir/paired/config.txt"
            processed_paired="1"  # paired has been processed
        fi
    else
        echo "BioProject directory $BioProjectDir does not exist."
    fi
done
