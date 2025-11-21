#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(eurostat)
  library(giscoR)
})

# ------------------------------------------------------------------------------
# Main function (single exported function)
# ------------------------------------------------------------------------------
#' Combine Eurostat population table with GISCO NUTS3 geometries
#'
#' @param country_code      Character, e.g. "DE"
#' @param nuts_year         Integer, NUTS version year (2013, 2016, 2021, 2024)
#' @param pop_year          Integer, population reference year
#' @param output_gpkg_path  Character, path to output GPKG file
#'
#' The function enforces valid combinations of NUTS year and population year:
#'   - NUTS 2013 -> POP 2014–2017
#'   - NUTS 2016 -> POP 2018–2020
#'   - NUTS 2021 -> POP 2021–2023
#'   - NUTS 2024 -> POP 2024–2030
#'
#' Output layer will contain a column "POP_<pop_year>" with population counts.
#'
combine_eurostat_data <- function(country_code,
                                  nuts_year,
                                  pop_year,
                                  output_gpkg_path) {
  
  message(sprintf(
    "D2K Wrapper Started for country: %s | NUTS: %s | Pop: %s",
    country_code, nuts_year, pop_year
  ))
  
  # --------------------------------------------------------------------------
  # 1. Validate and normalize inputs
  # --------------------------------------------------------------------------
  country_code <- toupper(country_code)
  if (!is.character(country_code) || nchar(country_code) != 2) {
    stop("country_code must be a 2-letter ISO country code (e.g. 'DE').")
  }
  
  if (!is.numeric(nuts_year) || !is.numeric(pop_year)) {
    stop("nuts_year and pop_year must be numeric (e.g. 2016, 2018).")
  }
  
  nuts_year <- as.integer(nuts_year)
  pop_year  <- as.integer(pop_year)
  
  # --------------------------------------------------------------------------
  # 2. Enforce allowed NUTS / POP year combinations
  # --------------------------------------------------------------------------
  # Valid year ranges:
  # - NUTS 2013 -> POP 2014–2017
  # - NUTS 2016 -> POP 2018–2020
  # - NUTS 2021 -> POP 2021–2023
  # - NUTS 2024 -> POP 2024–2030
  valid <- (
    (nuts_year == 2013 && pop_year >= 2014 && pop_year <= 2017) ||
      (nuts_year == 2016 && pop_year >= 2018 && pop_year <= 2020) ||
      (nuts_year == 2021 && pop_year >= 2021 && pop_year <= 2023) ||
      (nuts_year == 2024 && pop_year >= 2024 && pop_year <= 2030)
  )
  
  if (!valid) {
    msg <- paste0(
      "\n--- Valid Configurations ---\n",
      "NUTS 2013 -> Pop 2014-2017\n",
      "NUTS 2016 -> Pop 2018-2020\n",
      "NUTS 2021 -> Pop 2021-2023\n",
      "NUTS 2024 -> Pop 2024-2030\n",
      "----------------------------\n\n",
      "Requested: NUTS ", nuts_year, " with Pop ", pop_year,
      " is not supported.\n"
    )
    stop(msg)
  }
  
  # --------------------------------------------------------------------------
  # 3. Download NUTS3 geometries from GISCO (giscoR)
  # --------------------------------------------------------------------------
  message(sprintf(
    "Fetching NUTS3 boundaries (Year %s) from giscoR...",
    nuts_year
  ))
  
  nuts3_all <- giscoR::gisco_get_nuts(
    year         = nuts_year,
    nuts_level   = 3,
    resolution   = "01",
    cache        = TRUE,
    update_cache = FALSE,
    epsg         = "3035"     # ETRS89 / LAEA Europe (matches rest of workflow)
  )
  
  # Filter to requested country
  nuts3_country <- nuts3_all %>%
    dplyr::filter(CNTR_CODE == country_code)
  
  if (nrow(nuts3_country) == 0) {
    stop(
      "No NUTS3 polygons found for country_code = '",
      country_code, "' and nuts_year = ", nuts_year, "."
    )
  }
  
  # --------------------------------------------------------------------------
  # 4. Download Eurostat population table demo_r_pjangrp3
  # --------------------------------------------------------------------------
  message("Fetching Eurostat population table (demo_r_pjangrp3)...")
  
  poptable <- eurostat::get_eurostat("demo_r_pjangrp3",
                                     time_format = "date")
  
  # TIME_PERIOD in this dataset is stored as Date (e.g. "2018-01-01")
  pop_date <- as.Date(sprintf("%d-01-01", pop_year))
  
  # Filter to:
  #  - requested year
  #  - NUTS3 level codes (length 5)
  #  - total sex (T) and total age (TOTAL)
  message(sprintf("Filtering for population year: %d", pop_year))
  
  poptable_filtered <- poptable %>%
    dplyr::filter(
      TIME_PERIOD == pop_date,
      nchar(geo) == 5,
      sex == "T",
      age == "TOTAL"
    )
  
  # Filter to requested country (geo codes start with the country code)
  poptable_country <- poptable_filtered[grep(
    paste0("^", country_code),
    poptable_filtered$geo
  ), ]
  
  if (nrow(poptable_country) == 0) {
    stop(
      "No Eurostat population records found for country_code = '",
      country_code, "', pop_year = ", pop_year, "."
    )
  }
  
  # --------------------------------------------------------------------------
  # 5. Combine NUTS3 geometries with population table
  # --------------------------------------------------------------------------
  message(sprintf(
    "Filtering and combining Eurostat data for country: %s",
    country_code
  ))
  
  # Join on NUTS id
  nuts3_pop <- nuts3_country %>%
    dplyr::left_join(
      poptable_country,
      by = c("NUTS_ID" = "geo")
    )
  
  # Rename 'values' column to a year-specific population column
  pop_col_name <- paste0("POP_", pop_year)
  
  if (!"values" %in% names(nuts3_pop)) {
    stop("Joined dataset does not contain a 'values' column from Eurostat.")
  }
  
  names(nuts3_pop)[names(nuts3_pop) == "values"] <- pop_col_name
  
  # Optional: ensure numeric
  nuts3_pop[[pop_col_name]] <- as.numeric(nuts3_pop[[pop_col_name]])
  
  # --------------------------------------------------------------------------
  # 6. Write output as GeoPackage
  # --------------------------------------------------------------------------
  dir.create(dirname(output_gpkg_path), showWarnings = FALSE, recursive = TRUE)
  
  sf::st_write(
    nuts3_pop,
    dsn    = output_gpkg_path,
    layer  = "nuts3_pop",
    driver = "GPKG",
    delete_dsn = TRUE
  )
  
  message(
    sprintf(
      "D2K Wrapper Finished. NUTS3 population data saved to %s",
      output_gpkg_path
    )
  )
  
  invisible(output_gpkg_path)
}

# ------------------------------------------------------------------------------
# CLI wrapper (kept very simple for OGC/docker)
# ------------------------------------------------------------------------------
if (identical(environment(), globalenv())) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) != 4) {
    cat(
      "Error: Usage: Rscript src/combine_eurostat_data.R",
      "<country_code> <nuts_year> <pop_year> <output_gpkg_path>\n"
    )
    quit(status = 1)
  }
  
  country_code     <- args[1]
  nuts_year        <- as.integer(args[2])
  pop_year         <- as.integer(args[3])
  output_gpkg_path <- args[4]
  
  tryCatch(
    {
      combine_eurostat_data(
        country_code     = country_code,
        nuts_year        = nuts_year,
        pop_year         = pop_year,
        output_gpkg_path = output_gpkg_path
      )
    },
    error = function(e) {
      message("Error during script execution: ", e$message)
      quit(status = 1)
    }
  )
}