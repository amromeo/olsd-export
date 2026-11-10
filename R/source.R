# Public CHOP menu discovery and detail extraction. No browser runtime required.
menu_base <- "https://www.testmenu.com"

menu_text <- function(x) {
  trimws(gsub("[[:space:]\u00a0]+", " ", x, perl = TRUE))
}

menu_content_text <- function(node) {
  # Work on a copy so link/table extraction still sees the original structure.
  copy <- xml2::read_html(as.character(node))
  for (br in xml2::xml_find_all(copy, ".//br")) {
    xml2::xml_set_name(br, "span")
    xml2::xml_set_text(br, " ")
  }
  for (script in xml2::xml_find_all(copy, ".//sup|.//sub")) {
    marker <- if (xml2::xml_name(script) == "sup") "^" else "_"
    xml2::xml_set_text(script, paste0(marker, "{", xml2::xml_text(script), "}"))
    xml2::xml_set_name(script, "span")
  }
  menu_text(rvest::html_text2(copy))
}

menu_get <- function(path, body = NULL) {
  req <- httr2::request(paste0(menu_base, path)) |>
    httr2::req_user_agent("olsd-export/0.1 (public laboratory test catalog export)") |>
    httr2::req_timeout(60) |>
    httr2::req_retry(max_tries = 3)
  ca <- Sys.getenv("SSL_CERT_FILE")
  if (nzchar(ca)) req <- httr2::req_options(req, cainfo = ca)
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  response <- httr2::req_perform(req)
  httr2::resp_body_string(response)
}

menu_decode <- function(text) {
  result <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  # GetAll returns JSON encoded inside a JSON string.
  if (is.character(result) && length(result) == 1L) {
    result <- jsonlite::fromJSON(result, simplifyVector = FALSE)
  }
  result
}

menu_inventory <- function(fetch = menu_get, page_size = 100L, pause = 0.25) {
  index_text <- fetch("/api/CHOP/TestSearch/GetAll")
  index <- menu_decode(index_text)
  tests <- index$Tests
  ids <- vapply(tests, function(x) as.character(x$testId), "")
  if (!length(ids) || anyNA(ids) || anyDuplicated(ids) ||
      any(!grepl("^[0-9]+$", ids))) stop("Invalid or empty GetAll inventory")

  # Independently traverse the public search endpoint, including pagination.
  found <- character()
  raw_search <- list()
  page <- 1L
  total <- NULL
  repeat {
    Sys.sleep(pause)
    text <- fetch("/api/CHOP/TestSearch/", list(
      searchTerm = "", pageSize = page_size, pageNumber = page
    ))
    result <- menu_decode(text)
    reported <- result$totalResults
    if (length(reported) != 1L || !is.numeric(reported) ||
        reported < 1 || reported != as.integer(reported)) {
      stop("Invalid search total")
    }
    if (is.null(total)) total <- reported
    if (total != reported) stop("Inventory changed during search traversal")
    page_ids <- vapply(result$results, function(x) as.character(x$testId), "")
    expected <- min(page_size, total - length(found))
    if (length(page_ids) != expected || anyDuplicated(c(found, page_ids))) {
      stop("Incomplete or duplicated search page")
    }
    found <- c(found, page_ids)
    raw_search[[page]] <- text
    if (length(found) == total) break
    page <- page + 1L
  }
  if (length(ids) != total || !setequal(ids, found)) {
    stop("GetAll and paginated search inventories disagree")
  }
  # Other public lists must not silently introduce uncollected test identities.
  supplemental <- unlist(lapply(
    c("NewTests", "UpdatedTests", "PendingTests", "FutureTests", "InactiveTests"),
    function(key) vapply(index[[key]], function(x) as.character(x$testId), "")
  ), use.names = FALSE)
  category_ids <- unlist(lapply(index$CategoryTests, function(category) {
    vapply(category$Tests, function(x) as.character(x$testId), "")
  }), use.names = FALSE)
  if (length(setdiff(c(supplemental, category_ids), ids))) {
    stop("Public category/status lists contain IDs outside the main inventory")
  }
  list(tests = tests, count = length(ids), search_total = total,
       search_pages = page, raw_index = index_text, raw_search = raw_search)
}

menu_links <- function(node, url) {
  lapply(xml2::xml_find_all(node, ".//a[@href]"), function(a) {
    raw <- trimws(xml2::xml_attr(a, "href"))
    resolved <- xml2::url_absolute(raw, url)
    invalid <- length(resolved) != 1L || is.na(resolved)
    list(label = menu_text(rvest::html_text2(a)),
         url = if (invalid) raw else resolved, resolution_error = invalid)
  })
}

menu_tables <- function(node) {
  lapply(xml2::xml_find_all(node, ".//table"), function(table) {
    list(rows = lapply(xml2::xml_find_all(table, ".//tr"), function(row) {
      lapply(xml2::xml_find_all(row, "./th|./td"), function(cell) {
        list(text = menu_content_text(cell),
             header = xml2::xml_name(cell) == "th",
             rowspan = if (is.na(xml2::xml_attr(cell, "rowspan"))) "1" else xml2::xml_attr(cell, "rowspan"),
             colspan = if (is.na(xml2::xml_attr(cell, "colspan"))) "1" else xml2::xml_attr(cell, "colspan"))
      })
    }))
  })
}

menu_detail <- function(html, test) {
  doc <- xml2::read_html(html)
  id <- as.character(test$testId)
  url <- paste0(menu_base, "/chop/Tests/", id)
  page_id <- rvest::html_attr(rvest::html_element(doc, "input#TestId"), "value")
  if (is.na(page_id) || page_id != id) stop("Detail page identity mismatch: ", id)
  # The mobile accordion duplicates the desktop fields, including element IDs.
  root <- rvest::html_elements(doc, "#testSidebar > .hidden-phone > .tab-content")
  if (length(root) != 1L) stop("Unrecognized detail layout: ", id)
  if (length(xml2::xml_find_all(root, ".//*[@data-bind]"))) {
    stop("Detail content requires an additional dynamic-data adapter: ", id)
  }
  panes <- xml2::xml_find_all(root, "./div[contains(concat(' ', normalize-space(@class), ' '), ' tab-pane ')]")
  fields <- list()
  for (pane in panes) {
    group <- xml2::xml_attr(pane, "id")
    blocks <- xml2::xml_children(pane)
    for (block in blocks) {
      heading <- xml2::xml_find_all(block, "./h4")
      content <- xml2::xml_find_all(block, "./div[contains(concat(' ', normalize-space(@class), ' '), ' dataContent ')]")
      if (length(heading) != 1L || length(content) != 1L) {
        stop("Unrecognized detail field: ", id, " / ", group)
      }
      label <- menu_text(rvest::html_text2(heading))
      if (!nzchar(label)) stop("Unlabelled field: ", id)
      fields[[length(fields) + 1L]] <- list(
        section = group, label = label,
        text = menu_content_text(content),
        tables = menu_tables(content), links = menu_links(content, url),
        images = lapply(xml2::xml_find_all(content, ".//img[@src]"), function(img) {
          raw <- trimws(xml2::xml_attr(img, "src"))
          resolved <- xml2::url_absolute(raw, url)
          list(alt = if (is.na(xml2::xml_attr(img, "alt"))) "" else xml2::xml_attr(img, "alt"),
               url = if (length(resolved) != 1L || is.na(resolved)) raw else resolved)
        }),
        # Preserve superscript/subscript distinctions that plain text can lose.
        scripts = lapply(xml2::xml_find_all(content, ".//sup|.//sub"), function(n) {
          list(type = xml2::xml_name(n), text = menu_text(rvest::html_text2(n)))
        })
      )
    }
  }
  if (!length(fields)) stop("No detail fields: ", id)
  list(id = id, name = test$testName, number = test$testNumber,
       source_url = url, fields = fields)
}

menu_write_exports <- function(snapshot, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(snapshot, file.path(directory, "snapshot.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  tests <- do.call(rbind, lapply(snapshot$tests, function(test) {
    data.frame(id = test$id, name = test$name, number = test$number,
               source_url = test$source_url, fields = length(test$fields))
  }))
  field_rows <- list()
  link_rows <- list()
  image_rows <- list()
  table_rows <- list()
  for (test in snapshot$tests) {
    for (i in seq_along(test$fields)) {
      field <- test$fields[[i]]
      field_rows[[length(field_rows) + 1L]] <- data.frame(
        test_id = test$id, field_index = i, section = field$section,
        label = field$label, text = field$text
      )
      for (link in field$links) {
        link_rows[[length(link_rows) + 1L]] <- data.frame(
          test_id = test$id, field_index = i, label = link$label, url = link$url,
          resolution_error = isTRUE(link$resolution_error)
        )
      }
      for (image in field$images) {
        image_rows[[length(image_rows) + 1L]] <- data.frame(
          test_id = test$id, field_index = i, alt = image$alt, url = image$url
        )
      }
      for (t in seq_along(field$tables)) {
        rows <- field$tables[[t]]$rows
        for (r in seq_along(rows)) for (c in seq_along(rows[[r]])) {
          cell <- rows[[r]][[c]]
          table_rows[[length(table_rows) + 1L]] <- data.frame(
            test_id = test$id, field_index = i, table_index = t, row = r, column = c,
            text = cell$text, header = cell$header,
            rowspan = cell$rowspan, colspan = cell$colspan
          )
        }
      }
    }
  }
  sheets <- list(Tests = tests, Fields = do.call(rbind, field_rows))
  if (length(link_rows)) sheets$Links <- do.call(rbind, link_rows)
  if (length(image_rows)) sheets$Images <- do.call(rbind, image_rows)
  if (length(table_rows)) sheets$TableCells <- do.call(rbind, table_rows)
  # Excel has a hard cell-length limit. Preserve overflow in numbered chunks
  # rather than truncating content or failing an otherwise complete catalog.
  long_text <- list()
  for (sheet_name in names(sheets)) {
    sheet <- sheets[[sheet_name]]
    for (column_name in names(sheet)) {
      values <- sheet[[column_name]]
      if (!is.character(values)) next
      for (row in which(nchar(values) > 32767)) {
        value <- values[[row]]
        starts <- seq(1L, nchar(value), by = 30000L)
        for (part in seq_along(starts)) {
          long_text[[length(long_text) + 1L]] <- data.frame(
            sheet = sheet_name, row = row, column = column_name, part = part,
            text = substr(value, starts[part], starts[part] + 29999L)
          )
        }
        sheet[[column_name]][row] <- paste0("See LongText: ", sheet_name, " row ", row, " column ", column_name)
      }
    }
    sheets[[sheet_name]] <- sheet
  }
  if (length(long_text)) sheets$LongText <- do.call(rbind, long_text)
  writexl::write_xlsx(sheets, file.path(directory, "snapshot.xlsx"))
  invisible(directory)
}
