source(file.path("..", "..", "R", "source.R"))

testthat::test_that("Excel overflow preserves full text in JSON and ordered chunks", {
  text <- paste(rep("abcdefghij", 4000), collapse = "")
  snapshot <- list(tests = list(list(id = "1", name = "Long test", number = "L",
    source_url = "https://example.test/1", fields = list(list(section = "Notes",
      label = "Instructions", text = text, links = list(), tables = list())))))
  directory <- tempfile()
  menu_write_exports(snapshot, directory)
  stored <- jsonlite::fromJSON(file.path(directory, "snapshot.json"), simplifyVector = FALSE)
  testthat::expect_identical(stored$tests[[1]]$fields[[1]]$text, text)
  extracted <- tempfile(); dir.create(extracted)
  utils::unzip(file.path(directory, "snapshot.xlsx"), exdir = extracted)
  workbook <- xml2::read_xml(file.path(extracted, "xl", "workbook.xml"))
  sheets <- xml2::xml_find_all(workbook, "//*[local-name()='sheet']")
  testthat::expect_true("LongText" %in% xml2::xml_attr(sheets, "name"))
  part_xml <- xml2::read_xml(file.path(extracted, "xl", "worksheets", "sheet3.xml"))
  rows <- xml2::xml_find_all(part_xml, "//*[local-name()='row']")[-1]
  strings_path <- file.path(extracted, "xl", "sharedStrings.xml")
  strings <- if (file.exists(strings_path)) {
    xml2::xml_text(xml2::xml_find_all(xml2::read_xml(strings_path), "//*[local-name()='si']"))
  } else character()
  chunks <- vapply(rows, function(row) {
    cell <- tail(xml2::xml_find_all(row, "./*[local-name()='c']"), 1)
    if (identical(unname(xml2::xml_attr(cell, "t")), "s")) {
      index <- as.integer(xml2::xml_text(xml2::xml_find_first(cell, "./*[local-name()='v']")))
      strings[index + 1L]
    } else paste(xml2::xml_text(xml2::xml_find_all(cell, ".//*[local-name()='t']")), collapse = "")
  }, "")
  testthat::expect_identical(paste(chunks, collapse = ""), text)
})
