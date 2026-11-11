source(file.path("..", "..", "R", "source.R"))
source(file.path("..", "..", "R", "history.R"))

testthat::test_that("invalid or missing Connect storage configuration cannot fall back locally", {
  withr::local_envvar(c(POSIT_PRODUCT = "CONNECT", RSTUDIO_PRODUCT = NA, OLSD_STORE = NA))
  testthat::expect_error(history_store(), "OLSD_STORE is missing")
  Sys.setenv(OLSD_STORE = "local")
  testthat::expect_error(history_store(), "must be connect")
  Sys.setenv(OLSD_STORE = '"connect"')
  testthat::expect_error(history_store(), "Invalid OLSD_STORE")
  Sys.setenv(OLSD_STORE = " CONNECT ")
  testthat::expect_identical(history_store(), "connect")
  withr::local_envvar(c(CONNECT_SERVER = NA, CONNECT_API_KEY = NA))
  testthat::expect_error(history_board(), "CONNECT_SERVER, CONNECT_API_KEY")
  Sys.setenv(CONNECT_SERVER = "https://user:password@example.org/connect/", CONNECT_API_KEY = "test-key")
  logs <- testthat::capture_messages(testthat::expect_error(history_board(), "without credentials"))
  testthat::expect_false(any(grepl("password|test-key", logs)))
})

testthat::test_that("storage preflight verifies a small pin without modifying the accepted baseline", {
  root <- tempfile(); dir.create(root)
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_PIN_PREFIX = "probe-test",
    CONNECT_API_KEY = "secret-value-must-not-be-printed"))
  board <- pins::board_folder(file.path(root, "board"), versioned = FALSE)
  baseline <- list(runs = list(list(id = "preserved-baseline")))
  pins::pin_write(board, baseline, name = history_name("index"), type = "rds")
  logs <- testthat::capture_messages(storage <- history_preflight(board))
  testthat::expect_true(storage$probe$verified)
  testthat::expect_true(pins::pin_exists(board, history_name("diagnostics")))
  testthat::expect_identical(history_manifest(board), baseline)
  testthat::expect_match(paste(logs, collapse = "\n"), "PREFLIGHT_OK")
  testthat::expect_false(any(grepl(Sys.getenv("CONNECT_API_KEY"), logs, fixed = TRUE)))
  testthat::expect_true(storage$variables_present$CONNECT_API_KEY)
  rows <- history_pin_rows(board)
  testthat::expect_true(rows$exists[rows$purpose == "Storage diagnostic"])
  testthat::expect_false(rows$exists[rows$purpose == "Last attempt"])
})

testthat::test_that("storage failure stops before any source requests and records a redacted failure", {
  root <- tempfile(); dir.create(root)
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_PIN_PREFIX = "blocked",
    OLSD_LOCK_PATH = file.path(root, "lock"), OLSD_OUTPUT_PATH = file.path(root, "runs"),
    CONNECT_API_KEY = "secret-value-must-not-be-printed"))
  board <- pins::board_folder(file.path(root, "board"), versioned = FALSE)
  requests <- 0L
  fetch <- function(...) { requests <<- requests + 1L; stop("unexpected source request") }
  testthat::local_mocked_bindings(.package = "pins", pin_write = function(...) {
    stop(paste("write denied", Sys.getenv("CONNECT_API_KEY")))
  })
  logs <- testthat::capture_messages(
    testthat::expect_error(history_collect(board, fetch, pause = 0.1), "write denied \\[REDACTED\\]"))
  testthat::expect_equal(requests, 0)
  failure <- jsonlite::fromJSON(list.files(file.path(root, "runs"), "failure.json", recursive = TRUE, full.names = TRUE))
  testthat::expect_identical(failure$stage, "PREFLIGHT_WRITE")
  testthat::expect_false(grepl(Sys.getenv("CONNECT_API_KEY"), failure$error, fixed = TRUE))
  testthat::expect_false(any(grepl(Sys.getenv("CONNECT_API_KEY"), logs, fixed = TRUE)))
})

testthat::test_that("server URLs and credential values are sanitized in diagnostics", {
  withr::local_envvar(c(CONNECT_SERVER = "https://user:password@example.org/connect/?token=hidden#fragment",
                        CONNECT_API_KEY = "secret-key"))
  safe <- history_safe_url(Sys.getenv("CONNECT_SERVER"))
  testthat::expect_identical(safe, "https://example.org/connect/")
  output <- history_redact(paste(Sys.getenv("CONNECT_SERVER"), Sys.getenv("CONNECT_API_KEY")))
  testthat::expect_false(grepl("password|hidden|secret-key", output))
  testthat::expect_match(output, "REDACTED")
})

testthat::test_that("preflight report forwards hidden-chunk progress to the console without collection", {
  root <- tempfile(); dir.create(root)
  repo <- normalizePath(file.path("..", ".."))
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_BOARD_PATH = file.path(root, "board"),
    OLSD_PIN_PREFIX = "report-probe", OLSD_PREFLIGHT_ONLY = "true"))
  httr2::local_mocked_responses(function(req) stop("A storage-only report must not fetch test-menu pages"))
  env <- new.env(parent = globalenv())
  env$params <- list(collect = TRUE, preflight_only = FALSE)
  markdown <- file.path(root, "preflight.md")
  logs <- testthat::capture_messages(knitr::knit(file.path(repo, "collector.Rmd"), output = markdown, envir = env, quiet = TRUE))
  text <- paste(readLines(markdown), collapse = "\n")
  testthat::expect_match(text, "Storage preflight passed")
  testthat::expect_match(text, history_diagnostics_version)
  testthat::expect_match(paste(logs, collapse = "\n"), "PREFLIGHT_OK")
  testthat::expect_match(paste(logs, collapse = "\n"), "REPORT_READY")
  testthat::expect_null(history_manifest(pins::board_folder(file.path(root, "board"))))
  testthat::expect_true(rmarkdown::output_metadata$get()$rsc_email_suppress_scheduled)
})

testthat::test_that("source transport timeouts are retried and identify their URL", {
  withr::local_envvar(c(OLSD_HTTP_TRACE = "true", CONNECT_API_KEY = NA))
  attempts <- 0L
  testthat::local_mocked_bindings(.package = "curl", curl_fetch_memory = function(...) {
    attempts <<- attempts + 1L
    stop(structure(list(message = "Timeout was reached: 0 bytes received", call = NULL),
      class = c("curl_error_operation_timedout", "curl_error", "error", "condition")))
  })
  logs <- testthat::capture_messages(testthat::expect_error(
    menu_get("/api/CHOP/TestSearch/GetAll"), "Source request failed: https://www.testmenu.com/api/CHOP/TestSearch/GetAll"))
  testthat::expect_equal(attempts, 3L)
  testthat::expect_match(paste(logs, collapse = "\n"), "SOURCE_HTTP_RETRY")
  testthat::expect_match(paste(logs, collapse = "\n"), "SOURCE_HTTP_FAILED")
})
