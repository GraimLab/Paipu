# Contributors: Leslie Smith

ml jq
ml ncbi_cli
ml ncbi-genome-download

#rm *json

#create file to read in as array
readarray -t mammals < input.txt

N=$(wc -l < input.txt)
#output file column names:
#echo "SPECIES,GENOME_ACCESSION,ASSEMBLY_NAME,ASSEMBLY_STATUS,RELEASE_DATE,HAS_ANNOTATION,ANNOTATION_PROVIDER,ANNOTATION_RELEASE_DATE" >> output.txt
for i in $(seq 0 $((N-1))); do echo ${mammals[$i]}; file_name=$( (echo ${mammals[$i]} | sed 's/ /_/g') );
datasets summary genome taxon "${mammals[$i]}" --reference >  ncbi_queries/${file_name}.json
sh ncbi_queries/json_parse.sh ${file_name};done 
