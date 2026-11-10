source(file.path("..", "..", "R", "source.R"))
source(file.path("..", "..", "R", "history.R"))

example_test <- function(id = "1", value = "2 mg/L") list(
  id = id, name = paste("Test", id), number = id, source_url = paste0("https://example.test/", id),
  fields = list(list(section = "Results", label = "Range", text = value,
                     tables = list(), links = list(), images = list(), scripts = list()))
)
example_snapshot <- function(tests) list(schema_version = "0.1", tests = tests)

testthat::test_that("diffs identify field edits without treating reordered fields as edits", {
  a <- example_test()
  b <- example_test(value = "3 mg/L")
  events <- catalog_diff(example_snapshot(list(a)), example_snapshot(list(b)))
  testthat::expect_length(events, 1)
  testthat::expect_equal(events[[1]]$before$text, "2 mg/L")
  testthat::expect_equal(events[[1]]$after$text, "3 mg/L")
  a$fields[[2]] <- list(section = "Ordering", label = "Lab", text = "Local")
  b <- a; b$fields <- rev(b$fields)
  testthat::expect_length(catalog_diff(example_snapshot(list(a)), example_snapshot(list(b))), 0)
  b$fields[[1]]$links <- list(list(label = "Guide", url = "https://example.test/guide.pdf"))
  changed_link <- catalog_diff(example_snapshot(list(a)), example_snapshot(list(b)))
  testthat::expect_length(changed_link, 1)
  testthat::expect_equal(changed_link[[1]]$after$links[[1]]$url, "https://example.test/guide.pdf")
})

testthat::test_that("missing, confirmed removal, and edited reappearance persist across runs", {
  a <- example_snapshot(list(example_test()))
  empty <- example_snapshot(list())
  first <- history_next(NULL, NULL, a)
  testthat::expect_true(first$baseline)
  testthat::expect_length(first$events, 0)
  missing <- history_next(list(absent = list()), a, empty)
  testthat::expect_equal(missing$events[[1]]$type, "missing")
  removed <- history_next(list(absent = missing$absent), empty, empty)
  testthat::expect_equal(removed$events[[1]]$type, "removed")
  again <- history_next(list(absent = removed$absent), empty, empty)
  testthat::expect_length(again$events, 0)
  returned <- history_next(list(absent = again$absent), empty,
                            example_snapshot(list(example_test(value = "5 mg/L"))))
  testthat::expect_equal(vapply(returned$events, `[[`, "", "type"), c("reappeared", "modified"))
  testthat::expect_length(returned$absent, 0)
  changed <- a; changed$schema_version <- "next"
  testthat::expect_error(history_next(NULL, a, changed), "migration requires review")
})

testthat::test_that("real pins round trips preserve baseline after failed detail collection", {
  root <- tempfile(); dir.create(root)
  withr::local_envvar(c(OLSD_PIN_PREFIX = "test", OLSD_LOCK_PATH = file.path(root, "lock"),
                        OLSD_OUTPUT_PATH = file.path(root, "runs")))
  board <- pins::board_folder(file.path(root, "board"), versioned = FALSE)
  fetch <- function(path, body = NULL) {
    if (grepl("GetAll", path)) return('{"Tests":[{"testId":"1","testName":"Test","testNumber":"T"}]}')
    if (!is.null(body)) return('{"totalResults":1,"results":[{"testId":"1"}]}')
    '<input id="TestId" value="1"><div id="testSidebar"><div class="hidden-phone"><div class="tab-content"><div class="tab-pane" id="Ordering"><div><h4>Lab</h4><div class="dataContent">Local</div></div></div></div></div></div>'
  }
  first <- history_collect(board, fetch, pause = 0.1)
  testthat::expect_true(first$baseline)
  manifest <- history_manifest(board)
  testthat::expect_length(manifest$runs, 1)
  testthat::expect_equal(history_snapshot(board, manifest$runs[[1]])$tests[[1]]$name, "Test")
  second <- history_collect(board, fetch, pause = 0.1)
  testthat::expect_equal(second$event_count, 0)
  index_calls <- 0L
  changed_inventory <- function(path, body = NULL) {
    if (grepl("GetAll", path)) {
      index_calls <<- index_calls + 1L
      if (index_calls == 2L) return('{"Tests":[{"testId":"2"}]}')
    }
    fetch(path, body)
  }
  testthat::expect_error(history_collect(board, changed_inventory, pause = 0.1), "Inventory changed during detail collection")
  testthat::expect_length(history_manifest(board)$runs, 2)
  broken <- function(path, body = NULL) {
    if (grepl("/Tests/", path)) stop("detail unavailable")
    fetch(path, body)
  }
  testthat::expect_error(history_collect(board, broken, pause = 0.1), "detail unavailable")
  testthat::expect_length(history_manifest(board)$runs, 2)
  testthat::expect_equal(pins::pin_read(board, history_name("last-attempt"))$status, "failed")
  testthat::expect_false(dir.exists(file.path(root, "lock")))
})
