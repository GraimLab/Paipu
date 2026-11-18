## Scripts

### Non-Mouse Data Processing

| Script | Purpose |
|---|---|
| `Species_Merge_Data.Rmd` | Combines raw non-mouse expression data and metadata |
| `Metadata_Harmonization.Rmd` | Cleans and harmonizes non-mouse metadata |
| `Species_Expression_Processing.Rmd` | Processes non-mouse expression data, including removal of low-quality samples, gene filtering, normalization, correlation-based duplicate removal, and PCA |
| `Species_Sex_Prediction.Rmd` | Predicts biological sex using expression data for non-mouse samples with missing sex metadata |


### Mouse Data Processing

| Script | Purpose |
|---|---|
| `Mouse_Merge_Data.Rmd` | Combines raw mouse expression data |
| `Mouse_Bulk_Metadata_Harmonization.Rmd` | Cleans and harmonizes mouse bulk metadata |
| `Mouse_Bulk_Expression_Processing.Rmd` | Processes mouse expression data, including removal of low-quality samples, gene filtering, normalization, and PCA |
| `Mouse_Sex_Prediction.Rmd` | Predicts biological sex using expression data for mouse samples with missing sex metadata |


### Human Data Processing

| Script | Purpose |
|---|---|
| `Treehouse_Preprocessing.Rmd` | Processes Treehouse expression data and metadata, including conversion of Ensembl IDs to HUGO gene symbols, metadata cleaning, and PCA |


### Cross-Species Data Integration

| Script | Purpose |
|---|---|
| `Species_Mouse_Merge_Processing.Rmd` | Combines non-mouse and mouse expression data and performs PCA |
| `Species_Mouse_Human_Merge_Processing.Rmd` | Combines Treehouse, non-mouse, and mouse expression data, followed by batch correction and PCA |


### Phylogenetic and Statistical Analyses

| Script | Purpose |
|---|---|
| `Phylogenetic_Tree.Rmd` | Creates a phylogenetic tree using species sample counts |
| `Metadata_Charts_Stats.Rmd` | Creates manuscript figures and performs statistical analyses |
