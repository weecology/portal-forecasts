library(testthat)
library(portalcasting)

context("checks that a production pipeline has been setup and run correctly")

# Source utility functions
source("test_utils.R")

# Get project paths
paths <- get_project_paths()
project_root <- paths$root
forecasts_dir <- paths$forecasts
metadata_file <- paths$metadata

test_that("essential folders exist",{
  fnames <- list.files(project_root)
  expect_true("forecasts" %in% fnames)
  expect_true("data" %in% fnames)
  expect_true("models" %in% fnames)
})

test_that("dir_config is present",{
  fnames <- list.files(project_root)
  expect_true("directory_configuration.yaml" %in% fnames)
})

test_that("forecasts directory has content", {
  expect_true(dir.exists(forecasts_dir))
  forecast_files <- list.files(forecasts_dir, pattern = "\\.csv$")
  expect_true(length(forecast_files) > 0)
})

test_that("forecasts metadata is accessible", {
  expect_true(file.exists(metadata_file))
  metadata <- read.csv(metadata_file)
  expect_true(is.data.frame(metadata))
  expect_true(nrow(metadata) > 0)
})