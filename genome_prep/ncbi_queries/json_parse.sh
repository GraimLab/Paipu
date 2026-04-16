#Contributors: Leslie Smith

mammal=$1
i="ncbi_queries/$1"
accession=( $(jq '.reports[0].current_accession' ${i}.json) );assembly_name=( $(jq '.reports[0].assembly_info.assembly_name' ${i}.json) );assembly_status=( $(jq '.reports[0].assembly_info.assembly_status' ${i}.json) ); release_date=( $(jq '.reports[0].assembly_info.release_date' ${i}.json) ); has_annotation=( $(jq 'has("reports") and (.reports[0] | has("annotation_info"))' ${i}.json) ); annot_provider=( $(jq '.reports[0].annotation_info.provider' ${i}.json) ); annot_release_dat=( $(jq '.reports[0].annotation_info.release_date' ${i}.json) ); echo "${mammal},${accession},${assembly_name},${assembly_status},${release_date},${has_annotation},${annot_provider},${annot_release_dat}" | sed 's/"//g' >> ncbi_queries/query_output_all.csv
if [[ "$has_annotation" == "true" ]]; then
    echo "${mammal},${accession},${assembly_name},${assembly_status},${release_date},${has_annotation},${annot_provider},${annot_release_dat}" \
        | sed 's/"//g' >> query_output_valid.csv
fi
