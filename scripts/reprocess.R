# Reparse a complete retained source directory into a NEW, empty pins namespace.
# Does not fetch the live website. Useful for reviewed extractor migrations.
source("R/source.R")
source("R/history.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript scripts/reprocess.R path/to/source")
archive <- normalizePath(args[[1]], mustWork = TRUE)
board <- history_board()
if (!is.null(history_manifest(board))) stop("Reprocessing requires an empty board/pin prefix; preserve the old history")
paths <- list.files(archive, full.names = TRUE)
times <- file.info(paths)$mtime
window <- list(first = format(min(times), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
               last = format(max(times), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
index_calls <- 0L
fetch_archive <- function(path, body = NULL) {
  name <- if (grepl("GetAll$", path)) {
    index_calls <<- index_calls + 1L
    if (index_calls == 1L) "inventory.json" else "inventory-end.json"
  } else if (!is.null(body)) {
    paste0("search-", body$pageNumber, ".json")
  } else paste0(sub(".*/", "", path), ".html")
  file <- file.path(archive, name)
  if (!file.exists(file)) stop("Archive is incomplete: ", name)
  paste(readLines(file, warn = FALSE), collapse = "\n")
}
print(history_collect(board, fetch_archive, pause = 0,
  source_mode = "archive", source_window = window))
