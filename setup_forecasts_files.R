library(zip)

args = commandArgs(trailingOnly = TRUE)

#' unZip and zip forecasts by forecast date
#'
#' @param type either zip or unzip
zip_unzip <- function(type=NULL){
  print("Unzipping forecasts files")
  proj_path <- paste0("forecasts/")
  forecasts_metadata =  paste0(proj_path, "forecasts_metadata.csv")
  metadata <- read.csv(forecasts_metadata)
  unique_dates <- unique(metadata$forecast_date)
  unique_dates = sort(unique_dates)

  if (type=="zip"){
    csv_file <- "_forecast_table.csv"
    yaml_file <- "_metadata.yaml"
    json_file <- "_model_forecast.json"

    for (forecast_day in unique_dates){
      id_date_files <- c()
      zipfile <- paste0(proj_path, "forecast_id_", forecast_day, ".zip")
      # Get all the values of that particular day in a data frame
      newdata <- subset(metadata, forecast_date == forecast_day, select=c(forecast_id, forecast_date))
      # for each forecast_id get 3 files
      All_ids <- newdata$forecast_id
      for (id in All_ids){
        csv_file_path  = paste0(proj_path, "forecast_id_", id, csv_file)
        yaml_file_path = paste0(proj_path, "forecast_id_", id, yaml_file)
        json_file_path = paste0(proj_path, "forecast_id_", id, json_file)
        id_date_files <- c(id_date_files, csv_file_path, yaml_file_path, json_file_path)
      }
      # First remove old zip file if exists
      unlink(zipfile)
      # zip all id_date_files
      zipr(zipfile, id_date_files, compression_level = 9)
      unlink(id_date_files)
    }
  }

  if (type=="unzip"){
    print("zipping forecasts files")
    # unzip files basing on unique_dates
    for (forecast_day in unique_dates){
      zipfile <- paste0(proj_path, "forecast_id_", forecast_day, ".zip")
      if(file.exists(zipfile)){
        unzip(zipfile, exdir = proj_path)
        unlink(zipfile)
      }
    }
  }

}

zip_unzip(args[1])
