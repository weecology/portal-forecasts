library(testthat)
library(portalcasting)

find_project_root <- function() {
  current_dir <- getwd()
  while (current_dir != "/" && current_dir != "") {
    if (file.exists(file.path(current_dir, "directory_configuration.yaml"))) {
      return(current_dir)
    }
    current_dir <- dirname(current_dir)
  }
  stop("Could not find project root directory")
}

get_project_paths <- function() {
  project_root <- find_project_root()
  list(
    root = project_root,
    forecasts = file.path(project_root, "forecasts"),
    metadata = file.path(project_root, "forecasts", "forecasts_metadata.csv")
  )
}

project_root <- find_project_root()
paths <- get_project_paths()
forecasts_dir <- paths$forecasts
metadata_file <- paths$metadata

context("forecast metadata tests")

test_that("cast metadata", {
  expect_true(dir.exists(forecasts_dir))
  expect_true(file.exists(metadata_file))
  metadata <- read.csv(metadata_file)
  expect_true(is.data.frame(metadata))
  expect_true(nrow(metadata) > 0)
})

context("production pipeline tests")

test_that("essential folders exist", {
  fnames <- list.files(project_root)
  expect_true("forecasts" %in% fnames)
  expect_true("data" %in% fnames)
  expect_true("models" %in% fnames)
})

test_that("dir_config is present", {
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