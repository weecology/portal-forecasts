library(portalr)
sessionInfo()
library(portalcasting)

#Update data and models
setup_production()

#Run fastest model for testing in dry run
portalcast(models = c("ESSS"))

#Evaluate model forecast
evaluate_forecast()

#Zip all forecasts files and evaluation
post_process()