# Requires: httr
download_zenodo_forecasts <- function(recid = "15306968",
                                       outdir = "forecasts",
                                       pattern = "forecasts/") {
  # Always start clean
  if (dir.exists(outdir)) unlink(outdir, recursive = TRUE, force = TRUE)
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  ua <- httr::user_agent("everwatch/zenodo-forecasts")
  # Resolve latest version
  rec <- httr::RETRY("GET", sprintf("https://zenodo.org/api/records/%s", recid), ua, times = 5, pause_base = 2)
  httr::stop_for_status(rec)
  latest_url <- httr::content(rec, as = "parsed", type = "application/json")$links$latest

  latest <- httr::RETRY("GET", latest_url, ua, times = 5, pause_base = 2)
  httr::stop_for_status(latest)
  latest_parsed <- httr::content(latest, as = "parsed", type = "application/json")

  # Prefer single archive download if exposed by the API
  archive_url <- latest_parsed$links$archive
  tmp_root <- file.path(tempdir(), paste0("zenodo_", recid, "_", Sys.getpid()))
  dir.create(tmp_root, recursive = TRUE, showWarnings = FALSE)

  downloaded <- character(0)

  if (!is.null(archive_url)) {
    # Download one big zip of all files
    zip_path <- file.path(tmp_root, "all_files.zip")
    message("Downloading single archive: ", archive_url)
    resp <- httr::RETRY("GET", archive_url, ua,
                        httr::write_disk(zip_path, overwrite = TRUE),
                        httr::progress(type = "down"),
                        times = 5, pause_base = 2)
    httr::stop_for_status(resp)
    downloaded <- c(downloaded, zip_path)
  } else {
    # Fallbacks: if there is exactly one file (likely a zip), download it;
    # otherwise loop through files (no way around it in this case).
    files <- latest_parsed$files
    if (length(files) == 0) stop("No files on latest version of record ", recid)
    if (length(files) == 1) {
      f <- files[[1]]
      url <- if (!is.null(f$links$download)) f$links$download else f$links$self
      dest <- file.path(tmp_root, f$key)
      message("Downloading single file: ", f$key)
      resp <- httr::RETRY("GET", url, ua,
                          httr::write_disk(dest, overwrite = TRUE),
                          httr::progress(type = "down"),
                          times = 5, pause_base = 2)
      httr::stop_for_status(resp)
      downloaded <- c(downloaded, dest)
    } else {
      message("No archive link; downloading multiple files (fallback).")
      for (f in files) {
        url <- if (!is.null(f$links$download)) f$links$download else f$links$self
        dest <- file.path(tmp_root, f$key)
        dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
        message("Downloading ", f$key)
        resp <- httr::RETRY("GET", url, ua,
                            httr::write_disk(dest, overwrite = TRUE),
                            httr::progress(type = "down"),
                            times = 5, pause_base = 2, terminate_on = c(403, 404))
        httr::stop_for_status(resp)
        downloaded <- c(downloaded, dest)
      }
    }
  }

  # Extract only paths matching `pattern` (default: "forecasts/")
  final_dir <- outdir
  dir.create(final_dir, recursive = TRUE, showWarnings = FALSE)

  extract_from_zip <- function(z, patt, out) {
    listing <- utils::unzip(z, list = TRUE)$Name
    hits <- grep(patt, listing, value = TRUE)
    if (length(hits) > 0) {
      utils::unzip(z, exdir = out, files = hits, junkpaths = TRUE, overwrite = TRUE)
      TRUE
    } else {
      # Check for nested zip files
      zip_files <- grep("\\.zip$", listing, value = TRUE)
      if (length(zip_files) > 0) {
        # Extract nested zip to temp location
        temp_dir <- file.path(tempdir(), paste0("nested_", basename(z)))
        dir.create(temp_dir, showWarnings = FALSE)
        utils::unzip(z, files = zip_files, exdir = temp_dir)
        
        # Process each nested zip
        any_extracted <- FALSE
        for (zip_file in zip_files) {
          nested_zip <- file.path(temp_dir, zip_file)
          if (file.exists(nested_zip)) {
            nested_listing <- utils::unzip(nested_zip, list = TRUE)$Name
            nested_hits <- grep(patt, nested_listing, value = TRUE)
            if (length(nested_hits) > 0) {
              utils::unzip(nested_zip, exdir = out, files = nested_hits, junkpaths = TRUE, overwrite = TRUE)
              any_extracted <- TRUE
            }
          }
        }
        unlink(temp_dir, recursive = TRUE, force = TRUE)
        any_extracted
      } else FALSE
    }
  }

  extract_from_tar <- function(tarfile, patt, out) {
    listing <- utils::untar(tarfile, list = TRUE)
    hits <- grep(patt, listing, value = TRUE)
    if (length(hits) > 0) {
      # untar cannot junk paths selectively; extract to temp then flatten
      tmpx <- file.path(tempdir(), paste0("untar_", basename(tarfile), "_", as.integer(runif(1,1,1e9))))
      dir.create(tmpx, recursive = TRUE, showWarnings = FALSE)
      utils::untar(tarfile, files = hits, exdir = tmpx, tar = "internal")
      # copy over while dropping leading dirs
      for (h in hits) {
        src <- file.path(tmpx, h)
        dest <- file.path(out, basename(h))
        dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
        ok <- file.copy(src, dest, overwrite = TRUE, recursive = TRUE)
        if (!ok) warning("Failed to copy: ", h)
      }
      unlink(tmpx, recursive = TRUE, force = TRUE)
      TRUE
    } else FALSE
  }

  any_extracted <- FALSE
  for (p in downloaded) {
    if (grepl("\\.zip$", p, ignore.case = TRUE)) {
      any_extracted <- extract_from_zip(p, pattern, final_dir) || any_extracted
    } else if (grepl("\\.tar(\\.gz|\\.bz2|\\.xz)?$", p, ignore.case = TRUE)) {
      any_extracted <- extract_from_tar(p, pattern, final_dir) || any_extracted
    } else {
      # Non-archive: ignore
    }
  }

  # Clean up all temporary downloads
  unlink(tmp_root, recursive = TRUE, force = TRUE)

  if (!any_extracted) {
    message("No entries matching '", pattern, "' were found in the downloaded archive(s).")
  } else {
    message("Forecasts extracted to: ", normalizePath(final_dir))
  }

  return(final_dir)
}