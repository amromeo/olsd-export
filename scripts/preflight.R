# Storage-only check: no test-menu requests and no baseline/index changes.
source("R/source.R")
source("R/history.R")
storage <- history_preflight()
print(history_storage_rows(storage), row.names = FALSE)
