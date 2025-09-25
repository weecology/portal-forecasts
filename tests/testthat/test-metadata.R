library(testthat)

context("checks that forecasts exist for use")

# Source utility functions
source("test_utils.R")

# Get project paths
paths <- get_project_paths()
forecasts_dir <- paths$forecasts
metadata_file <- paths$metadata

test_that("cast metadata", {
  # Check if forecasts directory exists
  expect_true(dir.exists(forecasts_dir))
  
  # Check if metadata file exists
  expect_true(file.exists(metadata_file))
  
  # Try to read the metadata file
  metadata <- read.csv(metadata_file)
  expect_true(is.data.frame(metadata))
  expect_true(nrow(metadata) > 0)
})