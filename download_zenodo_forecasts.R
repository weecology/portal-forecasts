# Requires: httr

# Zenodo API URLs
ZENODO_SANDBOX_URL <- "https://sandbox.zenodo.org/api"
ZENODO_PRODUCTION_URL <- "https://zenodo.org/api"

# Concept record IDs for creating new versions
SANDBOX_CONCEPT_RECORD_ID <- "340647"
PRODUCTION_CONCEPT_RECORD_ID <- "10553210"

# Function to get latest published version from Zenodo
get_latest_published_version <- function(record_id, sandbox = FALSE) {
  base_url <- if (sandbox) ZENODO_SANDBOX_URL else ZENODO_PRODUCTION_URL
  content <- httr::content(httr::GET(paste0(base_url, "/records/", record_id)), "parsed")
  conceptrecid <- content$conceptrecid
  latest <- httr::content(httr::GET(paste0(base_url, "/records/", conceptrecid)), "parsed")
  latest$id
}

download_zenodo_forecasts <- function(recid = PRODUCTION_CONCEPT_RECORD_ID,
                                       outdir = "forecasts",
                                       pattern = "forecasts/") {
  # Create temporary directory for extraction
  temp_dir <- "forecasts_temp"
  if (dir.exists(temp_dir)) unlink(temp_dir, recursive = TRUE, force = TRUE)
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Prepare main output directory
  if (dir.exists(outdir)) unlink(outdir, recursive = TRUE, force = TRUE)
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  # Get latest version using concept record ID
  latest_recid <- get_latest_published_version(recid, sandbox = FALSE)
  message("Downloading latest version: ", latest_recid, " (from concept record: ", recid, ")")

  ua <- httr::user_agent("everwatch/zenodo-forecasts")
  latest <- httr::RETRY("GET", sprintf("https://zenodo.org/api/records/%s", latest_recid), ua, times = 5, pause_base = 2)
  httr::stop_for_status(latest)
  latest_parsed <- httr::content(latest, as = "parsed", type = "application/json")

  # Download and extract the archive
  archive_url <- latest_parsed$links$archive
  if (is.null(archive_url)) {
    stop("No archive link found for record ", latest_recid)
  }
  
  zip_path <- file.path(temp_dir, "portal-forecasts.zip")
  message("Downloading archive: ", archive_url)
  resp <- httr::RETRY("GET", archive_url, ua,
                      httr::write_disk(zip_path, overwrite = TRUE),
                      httr::progress(type = "down"),
                      times = 5, pause_base = 2)
  httr::stop_for_status(resp)
  
  # Extract the archive to temp directory
  message("Extracting archive...")
  utils::unzip(zip_path, exdir = temp_dir, overwrite = TRUE)
  
  # Extract the nested zip file
  nested_zip <- file.path(temp_dir, "weecology", "portal-forecasts-2025-04-30.zip")
  if (file.exists(nested_zip)) {
    message("Extracting nested archive...")
    utils::unzip(nested_zip, exdir = temp_dir, overwrite = TRUE)
  }
  
  # Find the forecasts directory dynamically in temp directory
  # Look for the weecology-portal-forecasts-* directory
  extracted_dirs <- list.dirs(temp_dir, full.names = FALSE, recursive = FALSE)
  portal_dir <- extracted_dirs[grepl("^weecology-portal-forecasts-", extracted_dirs)]
  
  if (length(portal_dir) == 0) {
    stop("Portal forecasts directory not found after extraction")
  }
  
  temp_forecasts_path <- file.path(temp_dir, portal_dir[1], "forecasts")
  if (!dir.exists(temp_forecasts_path)) {
    stop("Forecasts directory not found in: ", temp_forecasts_path)
  }
  
  # Copy forecasts contents to main output directory
  message("Copying forecasts to main directory...")
  file.copy(from = list.files(temp_forecasts_path, full.names = TRUE),
            to = outdir, 
            recursive = TRUE, 
            overwrite = TRUE)
  
  # Clean up temporary directory and zip files
  unlink(temp_dir, recursive = TRUE, force = TRUE)
  
  message("Forecasts copied to: ", normalizePath(outdir))
  return(outdir)
}