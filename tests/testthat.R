library(testthat)
library(portalcasting)

# Download forecasts from Zenodo before running tests
source("../download_zenodo_forecasts.R")
download_zenodo_forecasts()

test_dir("tests/testthat", reporter = c("check"))
