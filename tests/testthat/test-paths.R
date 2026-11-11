source(file.path("..", "..", "R", "history.R"))

testthat::test_that("root and generated local entry points share an existing baseline", {
  root <- tempfile(); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  dir.create(file.path(root, "scripts"))
  dir.create(file.path(root, "deploy", "app"), recursive = TRUE)
  dir.create(file.path(root, "deploy", "collector"), recursive = TRUE)
  writeLines("Package: olsdexport", file.path(root, "DESCRIPTION"))
  writeLines("# fixture", file.path(root, "scripts", "build-deploy.R"))
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_BOARD_PATH = NA,
    OLSD_PIN_PREFIX = "paths", OLSD_LOCK_PATH = NA, OLSD_OUTPUT_PATH = NA))
  withr::local_dir(root)
  board <- history_board()
  manifest <- list(runs = list(list(id = "existing-baseline", count = 1554L)))
  pins::pin_write(board, manifest, name = history_name("index"), type = "rds")
  for (directory in c("deploy/app", "deploy/collector")) {
    setwd(file.path(root, directory))
    testthat::expect_identical(history_manifest(history_board()), manifest)
    testthat::expect_identical(history_path("OLSD_BOARD_PATH", "outputs/board"), file.path(root, "outputs/board"))
    testthat::expect_identical(history_path("OLSD_LOCK_PATH", "outputs/collector.lock"), file.path(root, "outputs/collector.lock"))
    testthat::expect_identical(history_path("OLSD_OUTPUT_PATH", "outputs/runs"), file.path(root, "outputs/runs"))
    testthat::expect_false(dir.exists("outputs/board"))
  }
})

testthat::test_that("standalone bundles stay self-contained and explicit paths are respected", {
  root <- tempfile(); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  withr::local_dir(root)
  withr::local_envvar(c(OLSD_STORE = "local", OLSD_BOARD_PATH = NA))
  testthat::expect_identical(history_path("OLSD_BOARD_PATH", "outputs/board"), file.path(root, "outputs/board"))
  absolute <- file.path(root, "shared-board")
  Sys.setenv(OLSD_BOARD_PATH = absolute)
  testthat::expect_identical(history_path("OLSD_BOARD_PATH", "outputs/board"), absolute)
  Sys.setenv(OLSD_BOARD_PATH = "C:/shared/board")
  testthat::expect_identical(history_path("OLSD_BOARD_PATH", "outputs/board"), "C:/shared/board")
  Sys.setenv(OLSD_BOARD_PATH = "\\\\server\\share\\board")
  testthat::expect_identical(history_path("OLSD_BOARD_PATH", "outputs/board"), "\\\\server\\share\\board")
})

testthat::test_that("Connect working paths stay inside their content directory", {
  root <- tempfile(); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  dir.create(file.path(root, "scripts"))
  dir.create(file.path(root, "deploy", "collector"), recursive = TRUE)
  writeLines("Package: olsdexport", file.path(root, "DESCRIPTION"))
  writeLines("# fixture", file.path(root, "scripts", "build-deploy.R"))
  withr::local_envvar(c(OLSD_STORE = "connect", OLSD_OUTPUT_PATH = NA))
  withr::local_dir(file.path(root, "deploy", "collector"))
  testthat::expect_identical(history_path("OLSD_OUTPUT_PATH", "outputs/runs"),
    file.path(root, "deploy", "collector", "outputs/runs"))
})
