# Utility functions for tests
# This file contains shared functions used across test files

# Bootstrap function to find project root when this file is sourced from anywhere
bootstrap_project_root <- function() {
  current_dir <- getwd()
  while (current_dir != "/" && current_dir != "") {
    if (file.exists(file.path(current_dir, "directory_configuration.yaml"))) {
      return(current_dir)
    }
    current_dir <- dirname(current_dir)
  }
  stop("Could not find project root directory")
}

# Find project root directory (where directory_configuration.yaml is located)
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

# Get project paths
get_project_paths <- function() {
  project_root <- find_project_root()
  list(
    root = project_root,
    forecasts = file.path(project_root, "forecasts"),
    metadata = file.path(project_root, "forecasts", "forecasts_metadata.csv")
  )
}