source(file.path("..", "..", "R", "deployment.R"))

testthat::test_that("manifest validation rejects CRAN records without repository URLs", {
  file <- tempfile(fileext = ".json")
  jsonlite::write_json(list(packages = list(httr2 = list(Source = "CRAN", Repository = NULL))), file, auto_unbox = TRUE, null = "null")
  testthat::expect_error(deployment_check_manifest(file), "missing/invalid repository URLs for: httr2")
  jsonlite::write_json(list(packages = list(httr2 = list(Source = "CRAN", Repository = "https://cran.example.org"))), file, auto_unbox = TRUE)
  testthat::expect_silent(deployment_check_manifest(file))
})

testthat::test_that("an unavailable source index leaves both prior deployment directories intact", {
  root <- tempfile(); dir.create(root)
  jsonlite::write_json(list(R = list(Repositories = list(list(Name = "CRAN", URL = "https://cran.example.org")))), file.path(root, "renv.lock"), auto_unbox = TRUE)
  for (kind in c("app", "collector")) {
    dir.create(file.path(root, "deploy", kind), recursive = TRUE)
    writeLines("preserved", file.path(root, "deploy", kind, "manifest.json"))
  }
  previous <- getOption("repos")
  testthat::expect_error(deployment_build(root,
    index_reader = function(...) matrix(character(), nrow = 0, ncol = 0),
    writer = function(...) stop("must not generate manifests")), "No source package index could be read")
  testthat::expect_identical(getOption("repos"), previous)
  for (kind in c("app", "collector")) {
    testthat::expect_identical(readLines(file.path(root, "deploy", kind, "manifest.json")), "preserved")
  }
  dir.create(file.path(root, "R"))
  for (name in c("app.R", "collector.Rmd", "COPYRIGHT", "R/source.R", "R/history.R")) {
    writeLines("# fixture", file.path(root, name))
  }
  writer <- function(appDir, ...) {
    url <- if (basename(appDir) == "app") "https://cran.example.org" else NULL
    jsonlite::write_json(list(packages = list(example = list(Source = "CRAN", Repository = url))),
      file.path(appDir, "manifest.json"), auto_unbox = TRUE, null = "null")
  }
  testthat::expect_error(deployment_build(root,
    index_reader = function(...) matrix("example", nrow = 1, ncol = 1), writer = writer),
    "missing/invalid repository URLs")
  for (kind in c("app", "collector")) {
    testthat::expect_identical(readLines(file.path(root, "deploy", kind, "manifest.json")), "preserved")
  }
})

testthat::test_that("rsconnect can emit null repository URLs when its package index is unavailable", {
  root <- tempfile(); dir.create(root)
  writeLines('shiny::shinyApp(shiny::fluidPage("fixture"), function(input, output) {})', file.path(root, "app.R"))
  # Isolate repository resolution from unrelated lock/library version changes.
  packages <- setNames(lapply(c("jsonlite", "shiny"), function(name) {
    list(Package = name, Version = as.character(utils::packageVersion(name)),
         Source = "Repository", Repository = "CRAN")
  }), c("jsonlite", "shiny"))
  jsonlite::write_json(list(R = list(Version = as.character(getRversion()),
    Repositories = list(list(Name = "CRAN", URL = "https://cran.example.org"))),
    Packages = packages), file.path(root, "renv.lock"), auto_unbox = TRUE)
  # Reproduce dependency metadata generation without any network access.
  testthat::local_mocked_bindings(.package = "rsconnect", availablePackages = function(...) {
    matrix(character(), nrow = 0, ncol = 3,
      dimnames = list(NULL, c("Package", "Version", "Repository")))
  })
  rsconnect::writeManifest(appDir = root, appFiles = c("app.R", "renv.lock"),
                          appPrimaryDoc = "app.R", appMode = "shiny", quarto = FALSE)
  testthat::expect_error(deployment_check_manifest(file.path(root, "manifest.json")), "missing/invalid repository URLs")
})
