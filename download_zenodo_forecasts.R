ZENODO_URL <- "https://zenodo.org/api"

# Production concept record ID
PRODUCTION_CONCEPT_RECORD_ID <- "10553210"

get_latest_published_version <- function(record_id) {
  ua <- httr::user_agent("weecology/portal-forecasts")
  production_url <- "https://zenodo.org/api"
  response <- httr::RETRY("GET", sprintf("%s/records/%s", production_url, record_id), ua, times = 5, pause_base = 2)
  httr::stop_for_status(response)
  concept_data <- httr::content(response, as = "parsed", type = "application/json")
  latest_link <- concept_data$links$latest
  latest_record_id <- as.numeric(strsplit(latest_link, "/")[[1]][6])
  return(latest_record_id)
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
  latest_recid <- get_latest_published_version(recid)
  message("Downloading latest version: ", latest_recid, " (from concept record: ", recid, ")")

  ua <- httr::user_agent("weecology/portal-forecasts")
  latest <- httr::RETRY("GET", sprintf("%s/records/%s", ZENODO_URL, latest_recid), ua, times = 5, pause_base = 2)
  httr::stop_for_status(latest)
  latest_parsed <- httr::content(latest, as = "parsed", type = "application/json")

  # Download and extract the archive
  archive_url <- latest_parsed$links$archive
  if (is.null(archive_url)) {
    stop("No archive link found for record ", latest_recid)
  }
  cat("archive_url:", archive_url, "\n") # for debugging
  
  archive_path <- file.path(temp_dir, "portal-forecasts.zip")
  message("Downloading archive: ", archive_url)
  resp <- httr::RETRY("GET", archive_url, ua,
                      httr::write_disk(archive_path, overwrite = TRUE),
                      httr::progress(type = "down"),
                      times = 5, pause_base = 2)
  httr::stop_for_status(resp)
  zip_path <- archive_path

  # Extract the outer archive (contains portal-forecasts-YYYY-MM-DD.zip)
  message("Extracting outer archive...")
  utils::unzip(zip_path, exdir = temp_dir, overwrite = TRUE)
  
  # Find the inner zip file (portal-forecasts-YYYY-MM-DD.zip)
  inner_zip_files <- list.files(temp_dir, pattern = "portal-forecasts-.*\\.zip$", full.names = TRUE)
  
  if (length(inner_zip_files) == 0) {
    stop("Inner portal-forecasts archive not found after extraction")
  }
  
  # Extract the inner zip file (extracts directly into temp_dir)
  message("Extracting inner archive: ", basename(inner_zip_files[1]))
  utils::unzip(inner_zip_files[1], exdir = temp_dir, overwrite = TRUE)
  
  # The inner zip extracts directly into temp_dir, so forecasts/ is at temp_dir/forecasts/
  temp_forecasts_path <- file.path(temp_dir, "forecasts")
  
  # Verify forecasts directory exists
  if (!dir.exists(temp_forecasts_path)) {
    stop("Forecasts directory not found in: ", temp_forecasts_path)
  }
  
  # Copy archieve forecasts directory to main output forecasts directory
  message("Copying forecasts to main output directory...")
  file.copy(from = temp_forecasts_path,
            to = dirname(outdir),
            recursive = TRUE,
            overwrite = TRUE)
  
  # Clean up temporary directory
  # unlink(temp_dir, recursive = TRUE, force = TRUE)
  
  message("Forecasts copied to: ", normalizePath(outdir))
  return(outdir)
}