source(file.path("..", "..", "R", "source.R"))

testthat::test_that("inventory requires matching complete discovery routes", {
  tests <- lapply(1:3, function(i) list(testId = as.character(i)))
  fetch <- function(path, body = NULL) {
    value <- if (is.null(body)) list(Tests = tests) else {
      start <- (body$pageNumber - 1) * body$pageSize + 1
      list(totalResults = 3L, results = tests[start:min(3, start + body$pageSize - 1)])
    }
    jsonlite::toJSON(value, auto_unbox = TRUE)
  }
  inventory <- menu_inventory(fetch, page_size = 2, pause = 0)
  testthat::expect_equal(inventory$count, 3)
  testthat::expect_equal(inventory$search_pages, 2)
  broken <- function(path, body = NULL) {
    value <- menu_decode(fetch(path, body))
    if (!is.null(body) && body$pageNumber == 2) value$results <- list()
    jsonlite::toJSON(value, auto_unbox = TRUE)
  }
  testthat::expect_error(menu_inventory(broken, 2, 0), "Incomplete")
})

testthat::test_that("detail extraction preserves clinical structure and excludes mobile duplicates", {
  html <- paste0('<input id="TestId" value="42"><div id="testSidebar">',
    '<div class="row-fluid hidden-phone"><div class="tab-content">',
    '<div class="tab-pane" id="Results"><div><h4>Reference values</h4>',
    '<div class="dataContent"><p>10<sup>9</sup>/L</p>',
    '<table><tr><th>Age</th><th>Range</th></tr>',
    '<tr><td rowspan="2">Child</td><td>1–2</td></tr></table>',
    '<a href="../TestDirectory/SiteFile?fileName=guide.pdf">Guide</a>',
    '</div></div></div></div></div>',
    '<div id="accordionTests"><div class="tab-pane" id="Results">Duplicate</div></div></div>')
  test <- list(testId = "42", testName = "Example", testNumber = "EX")
  detail <- menu_detail(html, test)
  testthat::expect_length(detail$fields, 1)
  field <- detail$fields[[1]]
  testthat::expect_equal(field$tables[[1]]$rows[[2]][[1]]$rowspan, "2")
  testthat::expect_equal(field$scripts[[1]], list(type = "sup", text = "9"))
  testthat::expect_match(field$text, "10^{9}/L", fixed = TRUE)
  testthat::expect_equal(field$links[[1]]$url,
    "https://www.testmenu.com/chop/TestDirectory/SiteFile?fileName=guide.pdf")
  testthat::expect_error(menu_detail(sub('value="42"', 'value="43"', html), test), "identity")
  testthat::expect_error(menu_detail(sub('<h4>Reference values</h4>', '', html, fixed = TRUE), test), "Unrecognized")
  dynamic <- sub('<p>', '<p data-bind="text: pending">', html, fixed = TRUE)
  testthat::expect_error(menu_detail(dynamic, test), "dynamic-data adapter")
  reformatted <- gsub("<p>", "<p>\n  ", html, fixed = TRUE)
  testthat::expect_identical(menu_detail(html, test), menu_detail(reformatted, test))
  linebreaks <- xml2::read_html('<div>Negative<br>Positive</div>')
  testthat::expect_equal(menu_content_text(linebreaks), "Negative Positive")
  links <- menu_links(xml2::read_html('<a href=" https://example.test/guide.pdf ">Guide</a>'), "https://example.test/")
  testthat::expect_equal(links[[1]]$url, "https://example.test/guide.pdf")
  testthat::expect_false(links[[1]]$resolution_error)
})
