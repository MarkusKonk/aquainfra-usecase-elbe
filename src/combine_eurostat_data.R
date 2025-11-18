#!/usr/bin/env Rscript

################################################################################
# MODULE: Combine NUTS and Eurostat Population Data
#
# Fetches NUTS3 boundary data and Eurostat demographic data, automatically
# detects the latest available population year, filters the data, and merges
# population counts with the NUTS geometries for a specified country.
################################################################################

library(dplyr)
library(eurostat)
library(giscoR)
library(sf)

options(scipen = 100, digits = 4)

#' Combine NUTS3 Geometries with Eurostat Population Data
#' 
#' Filters NUTS3 geometries and Eurostat population table to a specific country 
#' and performs a spatial merge based on the NUTS ID.
#'
#' @param nuts3_all_sf sf object: All NUTS3 geometries (e.g., fetched from giscoR).
#' @param poptable_df data.frame: Filtered Eurostat population table containing 'geo' (NUTS_ID) and the 'POP_YYYY' column.
#' @param country_code character: The 2-letter country code (e.g., "DE").
#' @return sf object: NUTS3 geometries for the target country with the latest population data attached.
combine_eurostat_data <- function(nuts3_all_sf, poptable_df, country_code = "DE") {
  message(paste("Filtering and combining Eurostat data for country:", country_code))
  
  # Filter NUTS3 geometries for the target country
  nuts3_country <- nuts3_all_sf %>%
    dplyr::filter(CNTR_CODE == country_code)
  
  # Filter population table based on NUTS IDs starting with the country code
  country_pattern <- paste0("^", country_code)
  poptable_country <- poptable_df[grep(country_pattern, poptable_df$geo), ]
  
  # Merge NUTS geometries with population data
  nuts3pop_country <- merge(nuts3_country, poptable_country, 
                            by.x = "NUTS_ID", by.y = "geo", 
                            all.x = FALSE, all.y = FALSE)
  
  message("Eurostat data combination complete.")
  return(nuts3pop_country)
}

################################################################################
# D2K WRAPPER
################################################################################

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: Rscript src/combine_eurostat_data.R <country_code> <output_gpkg_path>", call. = FALSE)
}

param_country_code <- args[1]
param_year <- args[2]
output_path        <- args[3]

message(paste(
  "D2K Wrapper Started for country:", param_country_code,
  "and year:", param_year
))
message(paste("Output will be saved to:", output_path))

tryCatch({
  message("Fetching NUTS3 boundaries from giscoR...")
  # Fetches NUTS3 data for the latest available year (2021) in EPSG 3035 projection
  nuts3_all <- giscoR::gisco_get_nuts(
    year = param_year,
    epsg = "3035",
    resolution = "01",
    spatialtype = "RG",
    nuts_level = "3"
  )
  
  # (FIX) Changed "demo_r_pjanaggr3" to "demo_r_pjangrp3"
  message("Fetching Eurostat population table (demo_r_pjangrp3)...") 
  
  # Fetch data using the new, correct Eurostat table ID
  poptable <- eurostat::get_eurostat("demo_r_pjangrp3",
                                     time_format = "num",
                                     cache = FALSE)
  
  names(poptable) <- tolower(names(poptable))
  if (!"time" %in% names(poptable) && "time_period" %in% names(poptable)) {
    poptable <- poptable %>% rename(time = time_period)
  }
  
  # Clean up sex and age categories for filtering
  poptable <- poptable %>%
    mutate(
      sex = ifelse(sex %in% c("T", "Total", "TOTAL"), "T", sex),
      age = ifelse(age %in% c("TOTAL", "Total", "TOTAL_AGE"), "TOTAL", age)
    )
  
  # Find and use latest year for population data
  latest_year <- max(poptable$time, na.rm = TRUE)
  message(paste("Latest population year found:", latest_year))
  
  # Filter for the latest year, total population, total age, and NUTS3 level (nchar(geo) == 5)
  poptable_latest <- poptable %>%
    filter(time == latest_year, sex == "T", age == "TOTAL", nchar(geo) == 5) %>%
    select(geo, values)
  
  if (nrow(poptable_latest) == 0) {
    stop(paste("Filtering Eurostat data for year", latest_year, "resulted in 0 rows."))
  }
  
  # Rename 'values' to the dynamic, latest year column name (e.g., POP_2024)
  pop_col_name <- paste0("POP_", latest_year)
  names(poptable_latest)[names(poptable_latest) == "values"] <- pop_col_name
  
  
  nuts3_pop_data_sf <- combine_eurostat_data(
    nuts3_all_sf = nuts3_all,
    poptable_df = poptable_latest,
    country_code = param_country_code
  )
  
  sf::st_write(nuts3_pop_data_sf, output_path, delete_layer = TRUE, quiet = TRUE)
  
  message(paste("D2K Wrapper Finished. NUTS3 population data saved to", output_path))
  
}, error = function(e) {
  stop(paste("Error during script execution:", e$message))
})