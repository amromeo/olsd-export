# Run from the repository root: Rscript scripts/sample-export.R [output-directory]
source("R/source.R")
args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args)) args[[1]] else "outputs/feasibility"
dir.create(file.path(output, "source"), recursive = TRUE, showWarnings = FALSE)
inventory <- menu_inventory()
writeLines(inventory$raw_index, file.path(output, "source", "inventory.json"))
for (i in seq_along(inventory$raw_search)) {
  writeLines(inventory$raw_search[[i]], file.path(output, "source", paste0("search-", i, ".json")))
}
jsonlite::write_json(inventory$tests, file.path(output, "inventory.json"),
                     pretty = TRUE, auto_unbox = TRUE, null = "null")
# Representative initial sample: send-out, hematology tables, coagulation,
# pathology/document links, cytogenetics, pharmacogenomics, and chemistry.
sample_ids <- c("785763", "785260", "786124", "1224037", "785113", "1363450", "786502")
records <- list()
for (id in sample_ids) {
  test <- Filter(function(x) identical(as.character(x$testId), id), inventory$tests)
  if (length(test) != 1L) stop("Sample ID is no longer uniquely discoverable: ", id)
  Sys.sleep(0.25)
  html <- menu_get(paste0("/chop/Tests/", id))
  writeLines(html, file.path(output, "source", paste0(id, ".html")))
  records[[length(records) + 1L]] <- menu_detail(html, test[[1]])
}
snapshot <- list(
  schema_version = "0.1", purpose = "feasibility_sample", complete = FALSE,
  collected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  inventory_count = inventory$count, search_total = inventory$search_total,
  search_pages = inventory$search_pages, collected_count = length(records), tests = records
)
menu_write_exports(snapshot, output)
cat("Verified inventory:", inventory$count, "tests across", inventory$search_pages,
    "search pages. Sample exported:", length(records), "tests to", output, "\n")
