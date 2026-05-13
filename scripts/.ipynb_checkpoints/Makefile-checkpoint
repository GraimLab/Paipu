SHELL := /bin/bash

all: binBioProjects binSRABioProj createFREYAPhenotypeFile getConfigFile makeConfigFile downloadSRA runFREYA

binBioProjects: SRA_metadata.tsv
	echo "Executing binBioProjects..." >> makefile_log.txt
	# Print the BioProject (unique values) column to a new file sorted
	awk -F'\t' 'NR==1 { for (i=1; i<=NF; i++) if ($$i ~ /^bioproject$$/) colIndex=i } NR>1 { if (colIndex) print $$(colIndex) }' SRA_metadata.tsv | sort -u > BioProjIDs_tmp.txt \
	&& echo "BioProjIDs" > BioProjIDs.txt \
	&& cat BioProjIDs_tmp.txt >> BioProjIDs.txt \
	&& rm -f BioProjIDs_tmp.txt

	echo "Completed binBioProjects..." >> makefile_log.txt

binSRABioProj: binBioProjects
	echo "Executing binSRABioProj..." >> makefile_log.txt
	sh binSamples.sh
    
	# remove a directory and it's contents
	rm -r BioProjIDs
    
	echo "Completed binSRABioProj..." >> makefile_log.txt

createFREYAPhenotypeFile: binBioProjects
	echo "Executing createFREYAPhenotypeFile..." >> makefile_log.txt
	sh freya_phenotype.sh
	echo "Completed createFREYAPhenotypeFile..." >> makefile_log.txt

getConfigFile: binSRABioProj
	echo "Executing getConfigFile..." >> makefile_log.txt
	sh get_config.sh
	echo "Completed getConfigFile..." >> makefile_log.txt

makeConfigFile: getConfigFile
	echo "Executing makeConfigFile..." >> makefile_log.txt
	sh make_config.sh
	echo "Completed makeConfigFile..." >> makefile_log.txt

downloadSRA: makeConfigFile
	echo "Executing downloadSRA..." >> makefile_log.txt; \
	# Submit download_sra_from_list.sh and save all job IDs \
	job_id=$$(sbatch --parsable download_sra_from_list.sh /path/to/file/); \
	echo "$$job_id" | sed 's/,/\n/g' | awk '{print "afterok:" $$1}' | paste -sd ":" > sra_job_ids.txt; \
	if [ -z "$$job_id" ]; then \
		echo "Error: No job ID captured for downloadSRA." >> makefile_log.txt; \
		exit 1; \
	fi

runFREYA: downloadSRA
	echo "Executing runFREYA..." >> makefile_log.txt; \
	# Read job IDs from sra_job_ids.txt and submit run_freya.sh with dependencies
	job_ids=$$(cat sra_job_ids.txt); \
	sbatch --parsable --dependency=$$job_ids run_freya.sh;   