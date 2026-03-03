library(testthat)
library(portalcasting)

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

project_root <- bootstrap_project_root()

test_file(file.path(project_root, "tests", "testthat", "test-successful_forecasts.R"), reporter = c("check"))
