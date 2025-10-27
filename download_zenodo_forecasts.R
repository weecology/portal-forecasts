ZENODO_URL <- "https://zenodo.org/api"

# Production concept record ID
PRODUCTION_CONCEPT_RECORD_ID <- "10553210"

# Function to get latest published version from Zenodo
get_latest_published_version <- function(record_id) {
  15312542 # fixing the latest version
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

  # Extract the main archive first
  message("Extracting main archive...")
  utils::unzip(zip_path, exdir = temp_dir, overwrite = TRUE)
  
  # Look for nested archive in weecology directory
  weecology_dir <- file.path(temp_dir, "weecology")
  nested_zip_files <- list.files(weecology_dir, pattern = "portal-forecasts.*\\.zip$", full.names = TRUE)
  
  if (length(nested_zip_files) > 0) {
    # Option 1: Extract the nested zip file
    message("Found nested archive, extracting: ", basename(nested_zip_files[1]))
    utils::unzip(nested_zip_files[1], exdir = temp_dir, overwrite = TRUE)
    
    # Find the extracted portal forecasts directory (nested case)
    extracted_dirs <- list.dirs(temp_dir, full.names = FALSE, recursive = FALSE)
    portal_dir <- extracted_dirs[grepl("^weecology-portal-forecasts-", extracted_dirs)]
    
    if (length(portal_dir) == 0) {
      stop("Portal forecasts directory not found after nested extraction")
    }
    
    temp_forecasts_path <- file.path(temp_dir, portal_dir[1], "forecasts")
  } else {
    # Option 2: Extract the main portal-forecasts.zip file directly
    message("No nested archive found, extracting main portal-forecasts.zip")
    main_zip <- file.path(temp_dir, "portal-forecasts.zip")
    if (file.exists(main_zip)) {
      utils::unzip(main_zip, exdir = temp_dir, overwrite = TRUE)
    } else {
      stop("Main portal-forecasts.zip file not found")
    }
    
    # Find the extracted portal forecasts directory (direct case)
    extracted_dirs <- list.dirs(temp_dir, full.names = FALSE, recursive = FALSE)
    portal_dir <- extracted_dirs[grepl("^portal-forecasts-", extracted_dirs)]
    
    if (length(portal_dir) == 0) {
      stop("Portal forecasts directory not found after direct extraction")
    }
    
    temp_forecasts_path <- file.path(temp_dir, portal_dir[1], "forecasts")
  }
  
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