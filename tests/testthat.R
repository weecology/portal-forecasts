library(testthat)
library(portalcasting)

# Bootstrap function to find project root
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

# Get project root
project_root <- bootstrap_project_root()

# Source utility functions
source(file.path(project_root, "tests", "testthat", "test_utils.R"))

# Download forecasts from Zenodo before running tests
source(file.path(project_root, "download_zenodo_forecasts.R"))
download_zenodo_forecasts()

test_dir(file.path(project_root, "tests", "testthat"), reporter = c("check"))
