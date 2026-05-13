#!/bin/bash

function log {
    echo $(date +%F_%T) $$ $1
}

# Arguments:
#   - CSV file describing phenotypes. It should have three columns, e.g.:
#
#       SampleID,Histology,Patient
#       1A,N,1
#       1C,M,1
#       1E,B,1
#       1F,M,1
#
#     The first line is assumed to be a header line and is
#     discarded. This file is used to generate a list of fastq
#     files. For example, '1C' indicates we should process a fastq file
#     with the name:
#
#       ${FastqDir}/1C.fq.gz
#
#     The third column provides the id of the dog. Consolidated
#     results for a dog use this id as the basename for files.
#
#   - Directory containing fq.gz files (FastqDir above)
#   - Directory for storing output
#   - One or more stages, see list below (optional, if omitted all stages are run)

# Get current script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Set path for dexseq_count script
DEXSEQ_SCRIPT="${SCRIPT_DIR}/dexseq_count.py"

## Export all env variables from the config file
env_file=$(readlink -f $1)
set -o allexport
source ${env_file}
set +o allexport

phenoCsv=$2
fastqDir=$(readlink -f $3)
JOB_ID=$4
outDir=$(readlink -f $5) # added - changed from $4 to add slurm job id before it

log "Runnning on $(hostname)."

Stages="hisat2 fastqc dexcount aorrg markdup splitncr"

declare -A aaStages

doMe=1
for s in ${Stages}; do aaStages[$s]=${doMe}; done

shift 5 # added - changed to 5 since job id has been added as an arg
for s in $@
do
    if [[ ${aaStages[$s]+_} ]]
    then
	doMe=2
	aaStages[$s]=${doMe}
    else
	echo "Unknown processing stage: ""$s"", should be one of ${Stages}."
	exit 1
    fi
done


# The singularity image has many of the dependencies installed in
# standard locations, so we don't need to do much to PATH. See the
# Dockerfile used to create the docker image/container converted into
# the singularity image.  A few you other bits and pieces are located
# in this directory:
DISBATCH_ROOT=/apps/disbatch/2.5
export PYTHONPATH=${DISBATCH_ROOT}/disBatch:$PATH

# Set DB_TASK_PREFIX to something like "singularity run -B /file/system/path "
# if tasks need to be run via a singularity container.

function dbRetry () {
    # On some platforms, we've encountered sporadic SIGSEGV errors
    # with java. This wrapper function is used to invoke disBatch.py,
    # check for errors (reported in the status file produced by
    # disBatch.py) and rerun any tasks that failed the first time. If
    # the new run reports any failed tasks, we stop execution.

    bn=$1
    tpn=""
    [[ $# == 2 ]] && tpn="-t $2"
    
    log "Launching ${bn} tasks."
    
    p0="${bn}_db_${JOB_ID}_0" # added - changed to add job id
    disBatch --no-retire -p ${p0} ${tpn} "${outDir}/tasks/${bn}Tasks"
    sn0="${p0}_status.txt"
    if $(egrep -q '^R' ${sn0})
    then
	log "Detected errors in ${sn0}, rerunning."
	p1="${bn}_db_${JOB_ID}_1" # added - changed to add job id
	disBatch --no-retire -p ${p1} ${tpn} -r ${sn0} -R "${outDir}/tasks/${bn}Tasks"
	sn1="${p1}_status.txt"
	if $(egrep -q '^R' ${sn1})
	then
	    echo "Still errors in ${sn1}, giving up."
	    echo "Review and then consider running something like:"
	    echo "  disBatch.py -K -p ${p1/_1/_2} ${tpn} -r -R ${sn1} \"${outDir}/tasks/${bn}Tasks\""
	    exit 1
	fi
    fi
}

# Not all of these are currently used.
HapCallCores=14
Hisat2Cores=14
SplitNCRCores=14
VarFiltCores=14

mkdir -p ${outDir} && ( cd ${outDir} ; mkdir -p bams dexseq_count fastqc hisat2 logs tasks vcfs )

# We append to these files, so make sure they start clean (i.e., with just DB_TASK_PREFIX if specified).
pushd ${outDir}/tasks

hisat2Tasks_prefix='module load hisat2/${hisat2_version} && module load samtools/${samtools_version} && module list && '
fastqcTasks_prefix='module load fastqc/${fastqc_version} && '
dexTasks_prefix='module load htseq && '
aorrgTasks_prefix='module load picard/${picard_version} && '
mdTasks_prefix='module load picard/${picard_version} && '
sncrTasks_prefix='module load gatk/${gatk_version} && '
hcTasks_prefix='module load gatk/${gatk_version} && '
vfTasks_prefix='module load gatk/${gatk_version} && '
seTasks_prefix='module load snpeff/${snpeff_version} && '

for tf in hisat2Tasks fastqcTasks dexTasks aorrgTasks mdTasks sncrTasks hcTasks vfTasks seTasks
do
    pref=${tf}_prefix
    echo "#DISBATCH PREFIX ${!pref} " > ${tf}
done


popd

shopt -s nullglob

declare -A fqs1 fqs2 fqs missingfqs
if [[ ${aaStages["hisat2"]} == ${doMe} || ${aaStages["fastqc"]} == ${doMe} ]]
then
    # Sanity check the CSV file.
    for sample in $(awk -F, 'NR > 1{print $1}' ${phenoCsv})
    do
        fqs[${sample}]=${sample}
	fn="${fastqDir}/${sample}_1.fastq.gz"
	if [[ -e ${fn} ]]
	then
	    fqs1[${sample}]=${fn}
	else
	    missingfqs[${sample}]=${fn}
	fi
	fn="${fastqDir}/${sample}_2.fastq.gz"
        if [[ -e ${fn} ]]
        then
            fqs2[${sample}]=${fn}
        else
            missingfqs[${sample}]=${fn}
        fi
    done
fi
if [[ ${#missingfqs[@]} -gt 0 ]]
then
    echo "Missing fastqs:"
    for fq in "${!missingfqs[@]}"
    do
	echo "${fq}	${missingfqs[${fq}]}"
    done
    exit 1
fi


# Run hisat2 and fastqc
for bn in ${!fqs[@]}
do
    fn1=${fqs1[${bn}]}
    fn2=${fqs2[${bn}]}
    bam=${outDir}/hisat2/${bn}.bam
    
    echo "bash -c \"( hisat2 -x ${HSX} -1 ${fn1} -2 ${fn2} | samtools view -Sbh -o ${bam} - )\" &> ${outDir}/logs/${bn}_hisat2.log" >> ${outDir}/tasks/hisat2Tasks
    echo "fastqc  --quiet --outdir ${outDir}/fastqc ${fn1}" >> ${outDir}/tasks/fastqcTasks
done
[[ ${aaStages["hisat2"]} == ${doMe} ]] && { log "hisat2 tasks launched." ; dbRetry hisat2 ${TasksPerNode} ; }
[[ ${aaStages["fastqc"]} == ${doMe} ]] && { log "fastqc tasks launched." ; dbRetry fastqc ${TasksPerNode} ; }

# Run dexseq_count and vc prep.
for bam in ${outDir}/hisat2/*.bam
do
    bn=$(basename ${bam} .bam)

    echo "python ${DEXSEQ_SCRIPT} -p yes --format bam ${DC_GFF} ${bam} ${outDir}/dexseq_count/${bn}.txt &> ${outDir}/logs/${bn}_dexseq_count.log" >> ${outDir}/tasks/dexTasks
    echo "picard AddOrReplaceReadGroups TMP_DIR=${SLURM_TMPDIR} USE_JDK_DEFLATER=true USE_JDK_INFLATER=true I=${bam} O=${outDir}/bams/${bn}_sorted.bam SO=coordinate RGID=${bn} RGLB=${bn} RGPL=${RGPLParam} RGPU=${RGPUParam} RGSM=${bn} &> ${outDir}/logs/${bn}_aorrg.log" >> ${outDir}/tasks/aorrgTasks
    echo "picard MarkDuplicates TMP_DIR=${SLURM_TMPDIR} USE_JDK_DEFLATER=true USE_JDK_INFLATER=true I=${outDir}/bams/${bn}_sorted.bam O=${outDir}/bams/${bn}_dedupped.bam QUIET=true CREATE_INDEX=true VALIDATION_STRINGENCY=SILENT M=${outDir}/bams/${bn}_output.metrics &> ${outDir}/logs/${bn}_md.log" >> ${outDir}/tasks/mdTasks
    echo "gatk SplitNCigarReads --tmp-dir ${SLURM_TMPDIR} --use-jdk-deflater --use-jdk-inflater -R ${CFFA} -I ${outDir}/bams/${bn}_dedupped.bam -O ${outDir}/bams/${bn}_split.bam &> ${outDir}/logs/${bn}_sncr.log" >> ${outDir}/tasks/sncrTasks
done 
[[ ${aaStages["dexcount"]} == ${doMe} ]]  && { log "dexcount tasks launched." ; dbRetry dex ${TasksPerNode} ; }
[[ ${aaStages["aorrg"]} == ${doMe} ]]    && { log "aorrg tasks launched." ; dbRetry aorrg ${TasksPerNode} ; }
[[ ${aaStages["markdup"]} == ${doMe} ]]  && { log "markdup tasks launched." ; dbRetry md ${TasksPerNode} ; }
[[ ${aaStages["splitncr"]} == ${doMe} ]] && { log "splitncr tasks launched." ; dbRetry sncr ${TasksPerNode} ; }

# Remind the user to clean up after reviewing the results. Provide
# text of commands that can be cut-and-pasted to do so.
cat <<EOF
Check output. If it looks good, you can run these clean up commands:

/bin/rm -f ${outDir}/bams/*_sorted.bam ${outDir}/bams/*_dedupped.bam
/bin/rm -f ${outDir}/hisat2/*.bam
/bin/rm -f ${outDir}/vcfs/*_loc.vcf ${outDir}/vcfs/*_loc.vcf.idx

EOF
log "Done."
