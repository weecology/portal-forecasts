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
  )
}

project_root <- find_project_root()
paths <- get_project_paths()


context("production pipeline tests")

test_that("essential folders exist", {
  fnames <- list.files(project_root)
  expect_true("data" %in% fnames)
  expect_true("models" %in% fnames)
})

test_that("dir_config is present", {
  fnames <- list.files(project_root)
  expect_true("directory_configuration.yaml" %in% fnames)
})
