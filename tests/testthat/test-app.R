testthat::test_that("Shiny renders selected tests and before/after changes from pins", {
  root <- tempfile(); dir.create(root)
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_BOARD_PATH = file.path(root, "board"),
    OLSD_PIN_PREFIX = "app-test"))
  # Loading the app does not collect from the source or modify pins.
  app_env <- new.env(parent = globalenv())
  original <- getwd()
  setwd(file.path("..", ".."))
  on.exit(setwd(original), add = TRUE)
  sys.source("app.R", envir = app_env)
  board <- app_env$history_board()
  test <- list(id = "1", name = "Sample test", number = "SAMPLE",
    source_url = "https://www.testmenu.com/chop/Tests/1",
    fields = list(list(section = "Results", label = "Range", text = "2 mg/L",
      tables = list(), links = list(), images = list(), scripts = list())))
  snapshot <- list(schema_version = "0.1", tests = list(test))
  path <- file.path(root, "snapshot.json")
  jsonlite::write_json(snapshot, path, auto_unbox = TRUE)
  pins::pin_upload(board, path, name = "app-test-run-example")
  event <- list(test_id = "1", name = "Sample test", type = "modified", field = "Range",
                before = "1 mg/L", after = "2 mg/L")
  run <- list(id = "example", pin = "app-test-run-example", collected_at = app_env$utc_now(),
              count = 1L, baseline = FALSE, event_count = 1L, events = list(event))
  pins::pin_write(board, list(runs = list(run), absent = list()), name = "app-test-index", type = "rds")
  shiny::testServer(app_env$server, {
    session$setInputs(refresh = 1, run = "example", test = "1", type = "All", field = "",
      compare = FALSE, all_runs = FALSE, selected_only = FALSE,
      dates = c(as.character(Sys.Date() - 1), as.character(Sys.Date() + 1)), event = "1")
    testthat::expect_match(output$status, "Last accepted")
    testthat::expect_match(output$details$html, "Sample test")
    testthat::expect_match(output$details$html, "2 mg/L")
    testthat::expect_match(output$change$html, "1 mg/L")
    testthat::expect_match(output$change$html, "2 mg/L")
    session$setInputs(field = "unmatched")
    testthat::expect_match(output$change$html, "No changes match")
  })
})
