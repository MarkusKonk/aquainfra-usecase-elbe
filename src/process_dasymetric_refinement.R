#!/usr/bin/env Rscript

################################################################################
# MODULE: Dasymetric Refinement (Analysis Step 1)
#
# Performs the core dasymetric refinement logic. It combines NUTS3 population 
# data with weighted CORINE land cover polygons via spatial intersection, 
# calculates area-based normalized weights, and estimates population counts 
# for each CORINE segment (ancillary data).
################################################################################

# --- 1. DEPENDENCIES ---
library(sf)
library(dplyr)
library(units)
library(stringr) # Added for string detection

# --- 2. GLOBAL SETTINGS ---
options(scipen = 100, digits = 4)
options(timeout = 600)

# --- 3. FUNCTION DEFINITION (Corrected) ---
################################################################################

#' Perform Dasymetric Refinement to Create Ancillary Data
#' 
#' Intersects NUTS3 population data with weighted CORINE land cover, normalizes 
#' the weights based on NUTS region, and calculates the estimated population 
#' for each intersection segment. This output is the "ancillary data" used for 
#' subsequent interpolation.
#'
#' @param nuts3pop_sf sf object: NUTS3 data filtered to the analysis extent with population counts.
#' @param corine_vector_url character: URL or path to the CORINE vector data.
#' @param weight_table_df data.frame: The CORINE weight table (output of weighting_functions.R).
#' @param analysis_extent_sf sf object: The geometry defining the analysis boundary (unused in this function but kept for pipeline consistency).
#' @return sf object: Ancillary data (CORINE-NUTS segments) with the new column 'estPopCor'.
perform_dasymetric_refinement <- function(nuts3pop_sf, corine_vector_url, 
                                          weight_table_df, analysis_extent_sf) {
  
  message("Starting dasymetric refinement (Ground Truth Logic)...")
  
  # Dynamically find the population column (e.g., POP_2018, POP_2024)
  pop_col_name <- names(nuts3pop_sf)[stringr::str_starts(names(nuts3pop_sf), "POP_")][1]
  
  if (is.na(pop_col_name)) {
    stop("Error: No population column found in 'nuts3pop_sf'. Expected a column starting with 'POP_'.")
  }
  message(paste("Using population column:", pop_col_name))
  
  message("Downloading CORINE vector data to temp storage...")
  temp_cor_vector <- tempfile(fileext = ".gpkg")
  tryCatch({
    download.file(url = corine_vector_url, destfile = temp_cor_vector, mode = "wb", quiet = TRUE)
  }, error = function(e) {stop("Failed to download CORINE vector: ", e$message)})
  
  message("Loading CORINE vector from temp file...")
  cor_vector <- sf::st_read(temp_cor_vector, quiet = TRUE)
  
  # BUG FIX 1: Ensure column names match for joining (e.g., renaming 'Code_18' to 'CODE_18')
  names(cor_vector)[names(cor_vector) == "Code_18"] <- "CODE_18"
  
  # 1. Filter CORINE by populated classes (matching weight table)
  cor_detailed <- cor_vector[cor_vector$CODE_18 %in% weight_table_df$CODE_18,]
  
  # Convert to integer after filtering for clean merging
  cor_detailed$CODE_18 <- as.integer(cor_detailed$CODE_18)
  
  # 2. Merge the input weight ('percent') with the CORINE object
  cor_detailed_weights <- cor_detailed %>%
    left_join(weight_table_df, by = "CODE_18")
  
  message("Intersecting NUTS and weighted CORINE (this may take a while)...")
  # 3. Intersect the weighted CORINE data with the NUTS data
  nuts_cor_intersect <- sf::st_intersection(cor_detailed_weights, nuts3pop_sf)
  
  # 4. Create unique ID for CORINE-NUTS combinations
  nuts_cor_intersect$nuts_cor_id <- interaction(nuts_cor_intersect$NUTS_ID, nuts_cor_intersect$CODE_18)
  
  message("Calculating per-NUTS normalized weights...")
  
  # 5. Get unique CORINE weights per NUTS ID 
  table_unique_weights <- nuts_cor_intersect %>%
    as_tibble() %>%
    dplyr::select(nuts_cor_id, NUTS_ID, percent) %>%
    mutate(percent = as.numeric(percent)) %>%
    group_by(nuts_cor_id) %>%
    summarize(percUnique = first(percent), 
              NUTS_ID = first(NUTS_ID)) 
  
  # 6. Sum unique input weights per NUTS ID 
  table_sum_of_weights <- table_unique_weights %>%
    dplyr::select(NUTS_ID, percUnique) %>%
    group_by(NUTS_ID) %>%
    summarize(percSum = sum(percUnique, na.rm = TRUE)) 
  
  # 7. Merge the weight sum with the intersect data
  nuts_cor_weights <- nuts_cor_intersect %>%
    left_join(table_sum_of_weights, by = "NUTS_ID")
  
  # 8. Filter out non-NUTS areas
  nuts_cor_weights <- nuts_cor_weights %>%
    filter(!is.na(NUTS_ID) & NUTS_ID != "")
  
  # 9. Estimate final CORINE category input weight (normalized by NUTS)
  # newWeight: Normalized weight for that CORINE class *within* the NUTS region
  nuts_cor_weights$newWeight <- (as.numeric(nuts_cor_weights$percent) / nuts_cor_weights$percSum * 100.)
  
  # 10. Calculate intersection area
  nuts_cor_weights$area_cor <- units::set_units((sf::st_area(nuts_cor_weights)), km^2)
  
  # 11. Calculate area-weighted normalized weight
  nuts_cor_weights$area_corNum <- as.numeric(nuts_cor_weights$area_cor)
  nuts_cor_weights$areaWeight <- nuts_cor_weights$newWeight * nuts_cor_weights$area_corNum
  
  # 12. Get sum of area-based weights for each NUTS 
  table_area_weights <- nuts_cor_weights %>%
    as_tibble() %>%
    dplyr::select(NUTS_ID, areaWeight) %>%
    group_by(NUTS_ID) %>%
    summarize(areaWeightSum = sum(areaWeight, na.rm = TRUE)) 
  
  # 13. Merge the calculated area-based weights data
  nuts_cor_final <- nuts_cor_weights %>%
    left_join(table_area_weights, by = "NUTS_ID")
  
  # 14. New column with full area-based weights:  
  # areaWeightFull: Total weight contribution of this segment to the original NUTS population
  nuts_cor_final$areaWeightFull <- nuts_cor_final$areaWeight / nuts_cor_final$areaWeightSum 
  
  # 15. Estimate final population for this CORINE segment
  nuts_cor_final$estPopCor <- as.numeric(nuts_cor_final[[pop_col_name]]) * as.numeric(nuts_cor_final$areaWeightFull)
  
  # 16. Add unique ID for interpolation (required for sid in areal::aw_interpolate)
  nuts_cor_final$nuts_cor_int_id <- 1:nrow(nuts_cor_final)
  
  nuts_cor_final <- nuts_cor_final %>%
    filter(!is.na(estPopCor))
  
  # Clean up temp file
  file.remove(temp_cor_vector)
  message("Dasymetric refinement complete. Ancillary data created.")
  
  return(nuts_cor_final)
}

################################################################################
# --- 4. D2K EXECUTABLE WRAPPER ---
################################################################################

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 5) {
  stop("Usage: Rscript src/process_dasymetric_refinement.R <in_nuts3pop_path> <in_weight_table_rds_path> <in_analysis_extent_path> <corine_vector_url> <out_ancillary_data_path>", call. = FALSE)
}

# Assign arguments
path_nuts3pop     <- args[1] 
path_weight_table <- args[2] 
path_extent       <- args[3] 
url_corine_vector <- args[4]
output_path       <- args[5] 

message("D2K Wrapper Started. Reading input files for refinement...")

tryCatch({
  
  # Reading inputs 
  nuts3pop_sf <- sf::st_read(path_nuts3pop)
  weight_table_df <- readRDS(path_weight_table)
  analysis_extent_sf <- sf::st_read(path_extent)
  
  message("Running perform_dasymetric_refinement...")
  
  ancillary_data_sf <- perform_dasymetric_refinement(
    nuts3pop_sf = nuts3pop_sf,
    corine_vector_url = url_corine_vector,
    weight_table_df = weight_table_df,
    analysis_extent_sf = analysis_extent_sf
  )
  
  message(paste("Saving ancillary data to", output_path))
  sf::st_write(ancillary_data_sf, output_path, delete_layer = TRUE, quiet = TRUE)
  
  message("D2K Wrapper Finished. Ancillary data saved.")
  
}, error = function(e) {
  stop(paste("Error during script execution:", e$message))
})