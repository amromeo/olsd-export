# Run from repository root. Configuration is supplied through environment variables.
source("R/source.R")
source("R/history.R")
status <- history_collect()
cat(jsonlite::toJSON(status, auto_unbox = TRUE, pretty = TRUE), "\n")
