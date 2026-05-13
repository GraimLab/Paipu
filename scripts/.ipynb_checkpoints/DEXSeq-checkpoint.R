#script taken and slightly altered from https://github.com/flatironinstitute/FREYA/blob/master/DataAnalysis/prep_data.R

library("optparse")
library(tibble)
library(magrittr)
library(dplyr)

option_list <- list(
  make_option(c("-d", "--dataset"), type="character", default=NULL, 
              help="BioProject dataset name", metavar="character"),
  make_option(c("-m","--mammal"), type="character", default=0.5, 
              help="Mammal of analysis", metavar="character"),
  make_option(c("-l", "--layout"), type="character", default=NULL, 
              help="Bioproject Layout style (e.g., 'single' or 'paired')", metavar="character")
 ); 

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

studyID <- opt$dataset
mammal <- opt$mammal
layout <- opt$layout

# Get command line args used to run the script to get the script's file path
args <- commandArgs(trailingOnly = FALSE)

# Get file path to the current script and remove '--file=' from it
script_path <- sub("--file=", "", args[grep("--file=", args)])

# Get pipeline root directory
pipeline_dir <- normalizePath(file.path(dirname(script_path), ".."))

# Set FREYA results directory
datadir <- paste0(pipeline_dir,"/output/",mammal,"/",studyID,"/",layout,"/freya_results")

# make sample count files 
## Create the count files convert to gene level counts
print('Creating the count files'); flush.console()
fn.txt <- list.files(path=paste(datadir,"dexseq_count/",sep='/'), pattern="*.txt", full.names=FALSE, recursive=FALSE)
fn.txt <- paste(datadir, 'dexseq_count', fn.txt, sep='/')
for(fn in fn.txt) {
  print( paste('Processing sample', fn) ); flush.console()
  dat.fn <- read.table(fn, sep='\t', header=FALSE, stringsAsFactors=FALSE)
  ids.genes <- sapply(dat.fn$V1, function(x) {unlist(strsplit(x,':'))[1] } )
  
  dat <- aggregate(dat.fn[,2,drop=FALSE], by=list(ids.genes), FUN=sum)
  rownames(dat) <- dat$Group.1
  dat <- dat[,-1,drop=FALSE]
  dat <- dat[unique(ids.genes),,drop=FALSE]
  dat <- rownames_to_column(dat, "Genes")
  sampleid <- substr(basename(fn),1,nchar(basename(fn))-4)
  colnames(dat) <- c("Genes",sampleid)
  write.table( dat, file=paste(datadir,'dexseq_count',paste(tools::file_path_sans_ext(basename(fn)), 'count',sep='.'),sep='/'), sep ='\t', quote=FALSE, col.names=TRUE, row.names=FALSE ) 
}

fn.count <- list.files(path=paste(datadir,"dexseq_count/",sep='/'), pattern="*.count", full.names=FALSE, recursive=FALSE)
fn.count <- paste(datadir, 'dexseq_count', fn.count, sep='/')
newfiles <- lapply(fn.count, readr::read_tsv)
# - reduce to common genes - #
new.dat <- newfiles %>% purrr::reduce(inner_join)
dim(new.dat)
print(paste0('Study count matrix created: ', studyID, '.count')); flush.console()
write.table(new.dat, file=paste(datadir,'dexseq_count',paste(studyID, 'count', sep = '.'),sep='/'), sep ='\t', quote=FALSE, col.names=TRUE, row.names=FALSE ) 
