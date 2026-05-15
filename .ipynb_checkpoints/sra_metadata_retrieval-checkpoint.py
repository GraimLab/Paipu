#!/usr/bin/env python3
# coding: utf-8
import pandas as pd
import xml.etree.ElementTree as ET
import os
import shutil
import subprocess
import time
import re
from Bio import Entrez
from collections import Counter
from Levenshtein import distance as levenshtein_distance

# Set email address to access Entrez utilities
Entrez.email = os.getenv("ENTREZ_EMAIL")

# Set API key
Entrez.api_key = os.getenv("ENTREZ_API_KEY")

# Get the directory that contains this script
current_dir = os.path.dirname(os.path.abspath(__file__))

# Create output directory if it doesn't exist
output_dir = os.path.join(current_dir, "output")
os.makedirs(output_dir, exist_ok=True)

# Set path containing the pipeline scripts and Makefile
script_dir = os.path.join(current_dir, "scripts")

# Set path containing input files
input_dir = os.path.join(current_dir, "input")

# Define list of script file names to be copied to each organism's directory
file_names = ['binSamples.sh', 'download_sra_from_list.sh', 'freya_phenotype.sh',  'make_config.sh', 'get_config.sh', 'run_freya.sh', 'Makefile', 'run_deseq_count.sh']

# Create file paths for each script
script_files = [os.path.join(script_dir, file_name) for file_name in file_names]

# Read excluded col names for data harmonizing
exclude_df = pd.read_csv(os.path.join(input_dir,'exclude_cols.csv'))

# Convert the data to a set to exclude certain columns from renaming and for correct column names
exclude_cols = set(exclude_df['Excluded_Columns'])

# Read organisms and search terms from the csv file
query_df = pd.read_csv(os.path.join(input_dir,'query_info.csv'))

# Assuming 1st col: organisms; 2nd col: search terms - with headers
# Strip extra white space from the 1st two cols
for col in query_df.columns[:2]:
    query_df[col] = query_df[col].str.strip()

# Define keywords for the search query and drop any NAs
strategy = 'rna seq'
organisms = query_df.iloc[:, 0].dropna().tolist()
search_terms = query_df.iloc[:, 1].dropna().tolist()

################################
# Metadata retrieval functions #
################################

# Function to extract xml data from query results
def extract_data(result_xml):
    # List to append dictionary to then create a df 
    data = []

    root = ET.fromstring(result_xml)
    
    # Dictionary to keep results for the record
    record_data = {}

    def get_text(element, tag):
        try:
            return element.find(tag).text.strip()
        except AttributeError:
            return None

    def get_attribute(element, attribute):
        try:
            return element.attrib.get(attribute)         
        except AttributeError:
            return None

    # Experiment data
    record_data['Experiment Alias'] = get_attribute(root.find('.//EXPERIMENT'), 'alias')
    record_data['Experiment Accession'] = get_attribute(root.find('.//EXPERIMENT'), 'accession')
    record_data['Title'] = get_text(root, './/EXPERIMENT/TITLE')
    record_data['Study Name'] = get_text(root, './/EXPERIMENT/DESIGN/DESIGN_DESCRIPTION')
    record_data['Sample Accession'] = get_attribute(root.find('.//EXPERIMENT/DESIGN/SAMPLE_DESCRIPTOR'), 'accession')

    # Library data
    record_data['Library Name'] = get_text(root, './/EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_NAME')
    record_data['Library Strategy'] = get_text(root, './/EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_STRATEGY')
    record_data['Library Source'] = get_text(root, './/EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_SOURCE')
    record_data['Library Selection'] = get_text(root, './/EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_SELECTION')
    record_data['Library Construction Protocol'] = get_text(root, './/EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_CONSTRUCTION_PROTOCOL')
    library_layout_element = root.find('.//EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT')
    
    if library_layout_element is not None:
        # Extract the tag name of the child element (either single or paired)
        child_tag = library_layout_element[0].tag.strip()
        # Assign the tag name to 'Library Layout'
        record_data['Library Layout'] = child_tag
    else:
        record_data['Library Layout'] = None
    
    # Platform data
    record_data['Platform Instrument Model'] = get_text(root, './/EXPERIMENT/PLATFORM/ILLUMINA/INSTRUMENT_MODEL')

    # Submitter data
    record_data['Submitter Accession'] = get_attribute(root.find('.//SUBMISSION'),'accession')
    record_data['Submitter ID'] = get_text(root, './/SUBMISSION/IDENTIFIERS/SUBMITTER_ID')
    record_data['Submitter Title'] = get_text(root, './/SUBMISSION/TITLE')
    record_data['Organization Type'] = get_attribute(root.find('.//Organization'), 'type')
    record_data['Organization Name'] = get_text(root, './/Organization/Name')

    # Study data
    record_data['Study Accession'] = get_attribute(root.find('.//STUDY'), 'accession')
    record_data['BioSample'] = get_text(root, './/EXPERIMENT/DESIGN/SAMPLE_DESCRIPTOR/IDENTIFIERS/EXTERNAL_ID')
        
    external_id_element = root.find('.//STUDY/IDENTIFIERS/EXTERNAL_ID')
    if external_id_element is not None and 'namespace' in external_id_element.attrib:
        if external_id_element.attrib['namespace'] == 'BioProject':
            record_data['BioProject'] = external_id_element.text.strip()
        else:
            record_data['BioProject'] = None
    else:
        record_data['BioProject'] = None

    # Sample data
    record_data['Organism Tax ID'] = get_text(root, './/SAMPLE/SAMPLE_NAME/TAXON_ID')
    record_data['Organism Scientific Name'] = get_text(root, './/SAMPLE/SAMPLE_NAME/SCIENTIFIC_NAME')

    # Extract sample attributes
    sample_attributes_dict = {}
    for sample_attribute in root.findall('.//SAMPLE/SAMPLE_ATTRIBUTES/SAMPLE_ATTRIBUTE'):
        try:
            tag = sample_attribute.find('TAG').text.strip()
            value = sample_attribute.find('VALUE').text.strip()
            sample_attributes_dict[tag] = value
        except AttributeError:
            continue
            
    # Add sample attributes to record_data dictionary
    record_data.update(sample_attributes_dict)
    
     # Run data
    record_data['Run Accession'] = get_attribute(root.find('.//RUN_SET/RUN'), 'accession')
    record_data['Run Total Spots'] = get_attribute(root.find('.//RUN_SET/RUN'), 'total_spots')
    record_data['Run Total Bases'] = get_attribute(root.find('.//RUN_SET/RUN'), 'total_bases')
    record_data['Run Size'] = get_attribute(root.find('.//RUN_SET/RUN'), 'size')
    record_data['Run Load Done'] = get_attribute(root.find('.//RUN_SET/RUN'), 'load_done')
    record_data['Run Is Public'] = get_attribute(root.find('.//RUN_SET/RUN'), 'is_public')
    record_data['Run Has Tax Analysis'] = get_attribute(root.find('.//RUN_SET/RUN'), 'has_taxanalysis')

    # Base data
    bases_dict = {}
    for base_element in root.findall('.//RUN_SET/RUN/Bases/Base'):
        try:
            base_value = base_element.attrib.get('value')
            base_count = int(base_element.attrib.get('count'))
            bases_dict[base_value + ' Count'] = base_count
        except (AttributeError, ValueError):
            continue

    # Add base data to record_data dictionary
    record_data.update(bases_dict)

    # Add all data to data list and put into a df
    data.append(record_data)
    df = pd.DataFrame(data)
    
    return df

####################################
# Metadata harmonization functions #
####################################

# Function to combine cols with similar names
def combine_columns(df):
    # Normalize col names
    def normalize_column_name(name):
        return name.lower().replace('_', '').replace(' ', '').replace('-', '')
    
    # Store mappings of normalized column names to their original names
    merge_mappings = {}
    
    # Iterate over column names and map normalized names to original names
    for name in df.columns:
        normalized_name = normalize_column_name(name)
        if normalized_name in merge_mappings:
            merge_mappings[normalized_name].append(name)
        else:
            merge_mappings[normalized_name] = [name]
    
    # df to store merged columns
    merged_columns = {}
    
    # Merge columns with similar names
    for similar_names in merge_mappings.values():
        if len(similar_names) > 1:
            merged_column = pd.concat([df[name].astype(str).fillna('') for name in similar_names], axis=1)
            merged_columns[similar_names[0]] = merged_column.apply(' '.join, axis=1) # combine values from similar cols
    

    # Drop original columns that were merged from the original df
    columns_to_drop = [col for names in merge_mappings.values() for col in names if col in merged_columns]
   
    df.drop(columns=columns_to_drop, inplace=True)
    
    # Concatenate the merged df with the original df
    merged_df = pd.DataFrame(merged_columns)
    df = pd.concat([df, merged_df], axis=1)
    
    return df

# Function to harmonize column names using Levenshtein distance method
def harmonize_column_names(df, correct_names, exclude_names, threshold=3):
    # Put the df column names into a list (only the ones that need to be updated will change)
    new_columns = df.columns.tolist()
    
    # Iterate over each column
    for index, col in enumerate(df.columns):
        # Check if a column is in the excluded list
        if col in exclude_names:
            continue
        
        closest_match = None
        min_distance = float('inf')
        
        # Find the closest match in correct_names using Levenshtein distance
        for name in correct_names:
            dist = levenshtein_distance(col, name)
            if dist < min_distance:
                min_distance = dist
                closest_match = name
        
        # Check if min Levenshtein distance is below or equal to the threshold, if so rename the column 
        if min_distance <= threshold:
            new_columns[index] = closest_match
    
    # Assign new column names
    df.columns = new_columns
    
    return df

# Function to remove 'nan' from columns in a df
def clean_text(text):
    if pd.isna(text):
        return ""
    return " ".join(dict.fromkeys(x for x in str(text).split() if x.lower() != "nan"))

# List of keywords referring to single cell
sc_keywords = ['single-cell', 'single cell', 'scRNA-seq', 'scRNAseq', 'scRNA', 'singlecell']

# Function to iterate through metadata to find keywords indicating single cell studies
def label_sequencing_type(row):
    for val in row:
        if not isinstance(val, str):
            continue # skip vals that aren't strings
            
        for keyword in sc_keywords:
            if keyword.lower() in val.lower():
                return 'single-cell'
    return 'bulk'

#################################
# Metadata filterting functions #
#################################

# Set of terms to check in rows for
term_set = set(search_terms)

# Remove '*' from words
term_set = {term[:-1] if term.endswith('*') else term for term in term_set}

# Set of columns to check if a term exists in them (for dropping rows)
check_cols_set = {'organization_name', 'biomaterial_provider', 'submitter_handle', 'submitter_title', 'library_name', 'submitter_id', 'submitted_sample_id', 'biospecimen_repository_sample_id', 'cause_of_death', 'submitted_subject_id', 'biosample', 'cancer_type', 'insdc_center_name', 'insdc_center_alias'}

# Function to check for terms that are in columns they shouldn't be in
# if any of the words show up in one of the check_cols_set:
#    check if any of the words also show up in the remaining columns (other columns):
#         if yes, keep the row
#         if no, don't keep the row
def filter_df_rows(row, check_cols, other_cols, term_set):
    # Make terms lowercase (they should be already, but for consistency)
    term_set_lower = {term.lower() for term in term_set}

    # Filter out the columns from check_cols & other_cols that are actually in the df to avoid key errors
    actual_check_cols = [col for col in check_cols if col in row.index]
    actual_other_cols = [col for col in other_cols if col in row.index]

    # Check if any words from term_set appear anywhere within the row (only non-null values)
    row_contains_word = any(
    any(term in str(row[col]).lower() for term in term_set_lower) 
    for col in row.index if isinstance(row[col], (str, int, float)) and pd.notna(row[col]))

    if not row_contains_word:
        # If no search term is in the row, drop it
        return False

    # Check if any search term from term_set appear in actual_check_cols (only non-null values)    
    check_found = any(any(term in str(row[col]).lower() for term in term_set_lower) for col in actual_check_cols if pd.notna(row[col]))
    
    if check_found:
        # If a word is found in check_columns, check if it's also in actual_other_cols (only non-null values)        
        other_found = any(any(term in str(row[col]).lower() for term in term_set_lower) for col in actual_other_cols if pd.notna(row[col]))
        return other_found
    
    # If no word is found in check_columns, but the row contains a search term, keep the row
    return True

# Function to check if a cancer type is a general term for filtering out (so specific terms are kept if duplicates exist)
def is_general_cancer_type(cancer_type):
    return any(term in cancer_type.lower() for term in ['cancer*', 'tumor*', 'onco*'])

#################
# Main metadata pipeline #
#################

# Set batch size for how much records to retrieve at a time
batch_size = 500

# Flag for cancer atlas use case: true for cancer atlas use case, otherwise false
prioritize_specific_cancer_types = True

# Iterate through each organism
for organism in organisms:
    # List to store processed dfs for each search term
    organism_dfs = []
    
    # Iterate through each search term
    for search_term in search_terms:
        # Create query variable based on keywords given
        search_query = f'{search_term} AND {organism}[organism] AND {strategy}[strategy]'
        
        # List to store metadata for the current query
        data_list = [] 

        # Starting index for batch retrieval
        start = 0 

        while True:
            # Search SRA for records matching the query
            with Entrez.esearch(db='sra', term=search_query, retstart=start, retmax=batch_size) as search_handle:
                search_results = Entrez.read(search_handle)

            # Retrieve SRA record IDs
            id_list = search_results['IdList']

            # Stop if no more records
            if not id_list:
                break

            for record_id in id_list:    
                try:
                    # Use efetch to fetch the detailed record in XML format
                    with Entrez.efetch(db='sra', id=record_id, rettype='xml') as fetch_handle:
                        result_xml = fetch_handle.read()
    
                    # Extract data from result_xml and append to the metadata list
                    data_list.append(extract_data(result_xml)) 
    
                    # Delay between efetch requests for API limits
                    time.sleep(0.4)
    
                except Exception as e:
                    print(f"Error fetching {record_id} for {organism} and {search_term}: {e}", flush=True)
                    continue  # continue to next record

            # Increment start for the next batch
            start += batch_size
                
            print(f'Start for the next batch: {start} with organism: {organism} and search term: {search_term}')

        # Check if data_list is empty
        if not data_list:
            # print(f'There was no data for organism: {organism} and Search term: {search_term}')
            continue # move on to the next search term
        
        ## Otherwise, process the data:

        # Create a data frame for the current organism and store it in the dictionary
        initial_df = pd.concat(data_list, ignore_index=True)

        # Combine duplicate cols for the current organism
        term_df = combine_columns(initial_df)

        # Add search_term col
        term_df['search_terms'] = search_term

        # Create a copy to avoid df fragmentation issues
        term_df = term_df.copy()
        
        # Standardize col names by replacing special characters with an underscore
        term_df = term_df.rename(columns=lambda x: re.sub(r'[!?\+\-\*\s/:;\{\}\\()]+', '_', x))

        # Make all col names lowercase to fix mispelled col names
        term_df.columns = term_df.columns.str.lower()

        # Use Levenshtein distance to fix mispelled column names
        term_df = harmonize_column_names(term_df, exclude_cols, exclude_cols)

        # Merge duplicated columns again after harmonization
        term_df = combine_columns(term_df)
        
        # Store the processed df for the current search term
        organism_dfs.append(term_df)
        
    # Move on to the next organism if no data was retrieved
    if not organism_dfs:
        print(f"{organism} doesn't have any responses.")
        continue

    # Otherwise combine results for the current organism
    final_df = pd.concat(organism_dfs, ignore_index=True)

    # Combine duplicate columns for the current organism across search terms
    final_df = combine_columns(final_df)
    
    # Drop duplicate rows from the df; preserve search term col
    final_df = final_df.drop_duplicates(subset=final_df.columns.difference(['search_terms']))

    ## Check for terms that are in columns they shouldn't be in
    # Find cols that are not in check_cols_set and convert to a set for filtering
    other_cols_set = set(final_df.columns) - check_cols_set

    # Apply function to filter rows:
    #   If true, the row is kept. If false, the row is dropped
    filtered_final_df = final_df[final_df.apply(lambda row: filter_df_rows(row, check_cols_set, other_cols_set, term_set), axis=1)]

    # Drop any empty columns
    filtered_final_df = filtered_final_df.dropna(axis=1, how='all')

    # Move on to the next organism if no rows remain after filtering
    if filtered_final_df.empty:
        print(f"{organism} doesn't have any responses.")
        continue

    # Remove duplicate run accessions by keeping the most specific cancer type
    if prioritize_specific_cancer_types:
        # Add a temp column for whether a cancer type is general (0) or specific (1)
        filtered_final_df = filtered_final_df.assign(specific_cancer=filtered_final_df['search_terms'].apply(lambda x: 0 if is_general_cancer_type(x) else 1))

        # Sort by 'run_accession' and 'specific_cancer' so that specific cancer types would be first
        filtered_final_df = filtered_final_df.sort_values(by=['run_accession', 'specific_cancer'], ascending=[True, False])

        # Drop duplicates based on 'run_accession' and keep the row with the more specific cancer type
        filtered_final_df = filtered_final_df.drop_duplicates(subset='run_accession', keep='first')

        # Drop the temp column
        filtered_final_df = filtered_final_df.drop(columns=['specific_cancer'])

    # Remove duplicates by run_accession generally, keeping the 1st row
    else:
        filtered_final_df = filtered_final_df.drop_duplicates(subset='run_accession', keep='first')

    # Create organism directory
    organism_name = organism.replace(' ', '_') # create directory name based off the organism name
    organism_directory = os.path.join(output_dir, organism_name)
    os.makedirs(organism_directory, exist_ok=True)

    # Create log folder for FREYA
    os.makedirs(os.path.join(organism_directory, "freya_logs"), exist_ok=True)
    
    # Define output file paths
    csv_file_path = os.path.join(organism_directory, f'{organism_name}.csv')
    bioproj_csv_file_path = os.path.join(organism_directory, 'bioproject_info.csv')
    tsv_file_path = os.path.join(organism_directory, 'SRA_metadata.tsv')

    # Retrieve text metadata cols for cleaning
    text_cols = filtered_final_df.select_dtypes(include=['object', 'string']).columns

    # Clean df to remove 'nan' from entries
    filtered_final_df[text_cols] = filtered_final_df[text_cols].apply(lambda col: col.map(clean_text))

    # Labels samples as single-cell or bulk
    filtered_final_df['single_bulk'] = filtered_final_df.apply(label_sequencing_type, axis=1)
                
    # Output metadata to CSV and TXT file to the organism's directory
    filtered_final_df.to_csv(csv_file_path, index=False)
    filtered_final_df.to_csv(tsv_file_path, sep='\t', index=False, encoding='utf-8')

    # Select cols for BioProject info file
    cols_to_keep = ['bioproject', 'run_accession', 'library_layout', 'platform_instrument_model', 'organization_name']
                
    # Filter data for BioProject IDs, library layout, sequencer and submitter
    bioproj_df = filtered_final_df[cols_to_keep].copy()

    # Standardize BioProject sequencer and submitter values to be clean for config file
    for col in cols_to_keep[3:]:
        bioproj_df[col] = (bioproj_df[col]
        .astype(str) # set to string
        .str.upper() # make uppercase
        .str.replace(r'[^A-Z0-9]', '', regex=True)) # remove any symbols
    
    # Output bioproject data to CSV file to the organism's directory 
    bioproj_df.to_csv(bioproj_csv_file_path, index=False)

    # Copy Makefile and corresponding scripts to the organism's directory
    for script in script_files:
        shutil.copy(script, organism_directory, follow_symlinks = True)

    # Create Makefile file path
    makefile_path = os.path.join(organism_directory, 'Makefile')

    # Change directory to the organism's directory for the Makefile to run from and run downstream processing
    subprocess.run(['make', '-f', makefile_path], cwd = organism_directory, check=True)
