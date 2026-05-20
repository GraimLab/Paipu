# Analysis Script Descriptions:
- `Species_Merge_Data` - combine species expression data (raw) and metadata
- `Species_Expression_Processing` - remove low quality samples and filter genes, normalize, remove duplicates and PCA
- `Metadata_Harmonization` - clean and harmonize metadata
- `Metadata_Charts_Stats` - create bar graphs for paper figures and perform statistical tests
- `Species_Sex_Prediction` - predict biological sex using expression data for the species missing that information in their metadata
- `Phylogenetic_Tree` - create phylogenetic tree using organism sample counts
- `Treehouse_Preprocessing` - convert Ensembl IDs to hugo gene names, clean metadata to create bioproject, cancer types and cancer systems cols, raw PCA
- `Species_Human_Merge_Processing` - combine treehouse and mammal expression data and PCA