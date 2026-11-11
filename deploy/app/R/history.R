utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

display_time <- function(value) {
  time <- as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  format(time, "%Y-%m-%d %H:%M:%S %Z", tz = Sys.getenv("OLSD_DISPLAY_TZ", "America/New_York"))
}

history_diagnostics_version <- "storage-diagnostics-1"

history_on_connect <- function() {
  any(toupper(Sys.getenv(c("POSIT_PRODUCT", "RSTUDIO_PRODUCT"))) == "CONNECT")
}

history_store <- function() {
  raw <- trimws(Sys.getenv("OLSD_STORE"))
  if (!nzchar(raw)) {
    if (history_on_connect()) stop("OLSD_STORE is missing on Posit Connect. Set OLSD_STORE=connect before rendering.", call. = FALSE)
    return("local")
  }
  mode <- tolower(raw)
  if (!mode %in% c("local", "connect")) stop("Invalid OLSD_STORE: use local or connect (without quotes).", call. = FALSE)
  if (history_on_connect() && mode != "connect") {
    stop("OLSD_STORE must be connect on Posit Connect; local storage does not publish server pins.", call. = FALSE)
  }
  mode
}

history_flag <- function(variable, default = FALSE) {
  value <- tolower(trimws(Sys.getenv(variable, if (default) "true" else "false")))
  if (!value %in% c("true", "false")) stop(variable, " must be true or false (without quotes).", call. = FALSE)
  value == "true"
}

history_safe_url <- function(value) {
  if (is.null(value) || !length(value) || !nzchar(value)) return("")
  tryCatch({
    parsed <- httr2::url_parse(value)
    parsed$username <- NULL; parsed$password <- NULL
    parsed$query <- NULL; parsed$fragment <- NULL
    httr2::url_build(parsed)
  }, error = function(e) "(invalid URL)")
}

history_redact <- function(text) {
  key <- Sys.getenv("CONNECT_API_KEY")
  if (nzchar(key)) text <- gsub(key, "[REDACTED]", text, fixed = TRUE)
  server <- Sys.getenv("CONNECT_SERVER")
  if (nzchar(server)) text <- gsub(server, history_safe_url(server), text, fixed = TRUE)
  gsub("[\r\n]+", " ", text)
}

history_log <- function(stage, detail, run_id = NULL, journal = NULL) {
  event <- list(time = utc_now(), stage = stage, run_id = run_id, detail = history_redact(detail))
  message("OLSD ", event$time, " [", stage, "] ",
          if (!is.null(run_id)) paste0("run=", run_id, " ") else "", event$detail)
  if (!is.null(journal)) cat(jsonlite::toJSON(event, auto_unbox = TRUE, null = "null"), "\n", file = journal, append = TRUE)
  invisible(event)
}

history_pin_info <- function(board, name) {
  if (inherits(board, "pins_board_connect") && !grepl("/", name, fixed = TRUE)) {
    name <- paste0(board$account, "/", name)
  }
  meta <- pins::pin_meta(board, name)
  list(name = name, url = history_safe_url(meta$local$url),
       content_guid = if (is.null(meta$local$content_id)) "" else meta$local$content_id,
       directory = if (inherits(board, "pins_board_folder")) as.character(meta$local$dir) else "")
}

history_storage_info <- function(board) {
  mode <- if (inherits(board, "pins_board_connect")) "connect" else "local"
  variables <- c("OLSD_STORE", "OLSD_PIN_PREFIX", "CONNECT_SERVER", "CONNECT_API_KEY")
  list(diagnostics_version = history_diagnostics_version, checked_at = utc_now(),
    mode = mode, board_class = class(board)[1],
    server = if (mode == "connect") history_safe_url(board$url) else "",
    account = if (mode == "connect") board$account else "",
    directory = if (mode == "local") as.character(board$path) else "",
    working_directory = normalizePath(getwd(), winslash = "/"),
    content_guid = Sys.getenv("CONNECT_CONTENT_GUID"),
    source_revision = Sys.getenv("OLSD_SOURCE_REVISION", "unknown"),
    variables_present = as.list(setNames(nzchar(Sys.getenv(variables)), variables)),
    pin_prefix = Sys.getenv("OLSD_PIN_PREFIX", "olsd"))
}

history_preflight <- function(board = history_board()) {
  phase <- "BOARD"
  tryCatch({
  storage <- history_storage_info(board)
  phase <- "PREFLIGHT"
  history_log("PREFLIGHT", paste("mode=", storage$mode, "; board=", storage$board_class,
    "; destination=", if (storage$mode == "connect") storage$server else storage$directory,
    "; account=", storage$account, "; prefix=", storage$pin_prefix, sep = ""))
  name <- history_name("diagnostics")
  if (inherits(board, "pins_board_connect") && !grepl("/", name, fixed = TRUE)) {
    name <- paste0(board$account, "/", name)
  }
  nonce <- paste(sample(c(letters, 0:9), 16, replace = TRUE), collapse = "")
  probe <- list(checked_at = utc_now(), nonce = nonce, storage = storage)
  phase <- "PREFLIGHT_WRITE"
  history_log("PREFLIGHT_WRITE", paste("Writing small diagnostic pin", name))
  pins::pin_write(board, probe, name = name, type = "rds", title = "OLSD storage diagnostics")
  phase <- "PREFLIGHT_READ"
  history_log("PREFLIGHT_READ", paste("Reading diagnostic pin back", name))
  readback <- pins::pin_read(board, name)
  if (!identical(readback$nonce, nonce)) stop("Storage preflight readback mismatch", call. = FALSE)
  phase <- "PREFLIGHT_METADATA"
  storage$probe <- history_pin_info(board, name)
  storage$probe$verified <- TRUE
  history_log("PREFLIGHT_OK", paste("Write/read verified; pin=", storage$probe$name,
    "; URL=", storage$probe$url, "; content GUID=", storage$probe$content_guid, sep = ""))
  storage
  }, error = function(e) {
    detail <- history_redact(conditionMessage(e))
    history_log(paste0(phase, "_FAILED"), detail)
    stop(structure(list(message = detail, call = NULL, olsd_stage = phase),
                   class = c("olsd_storage_error", "error", "condition")))
  })
}

history_storage_rows <- function(storage) {
  values <- c("Diagnostics version" = storage$diagnostics_version,
    "Storage checked at" = display_time(storage$checked_at), "Storage mode" = storage$mode,
    "Board class" = storage$board_class, "Connect server" = storage$server,
    "Authenticated account" = storage$account, "Local board folder" = storage$directory,
    "Pin prefix" = storage$pin_prefix, "Working directory" = storage$working_directory,
    "Report content GUID" = storage$content_guid, "Source revision" = storage$source_revision)
  if (length(storage$variables_present)) {
    values <- c(values, setNames(ifelse(unlist(storage$variables_present), "set", "missing"),
                                 paste(names(storage$variables_present), "present")))
  }
  if (!is.null(storage$probe)) values <- c(values,
    "Storage write/read check" = if (isTRUE(storage$probe$verified)) "passed" else "not verified",
    "Diagnostic pin" = storage$probe$name, "Diagnostic pin URL" = storage$probe$url,
    "Diagnostic pin GUID" = storage$probe$content_guid)
  data.frame(setting = names(values), value = unname(values), row.names = NULL)
}

history_pin_rows <- function(board, run = NULL) {
  targets <- c("Storage diagnostic" = history_name("diagnostics"),
             "Accepted index" = history_name("index"), "Last attempt" = history_name("last-attempt"))
  if (!is.null(run)) targets <- c("Snapshot and exports" = run$pin, targets)
  do.call(rbind, lapply(seq_along(targets), function(i) {
    name <- targets[[i]]
    if (inherits(board, "pins_board_connect") && !grepl("/", name, fixed = TRUE)) name <- paste0(board$account, "/", name)
    exists <- pins::pin_exists(board, name)
    info <- if (exists) history_pin_info(board, name) else list(url = "", content_guid = "", directory = "")
    data.frame(purpose = names(targets)[i], name = name, exists = exists,
               url = info$url, content_guid = info$content_guid, directory = info$directory)
  }))
}

catalog_diff <- function(old, new) {
  events <- list()
  emit <- function(id, name, type, field = NULL, before = NULL, after = NULL) {
    events[[length(events) + 1L]] <<- list(
      test_id = id, name = name, type = type, field = field,
      before = before, after = after
    )
  }
  left <- setNames(old$tests, vapply(old$tests, `[[`, "", "id"))
  right <- setNames(new$tests, vapply(new$tests, `[[`, "", "id"))
  for (id in setdiff(names(right), names(left))) {
    emit(id, right[[id]]$name, "added", after = right[[id]])
  }
  for (id in setdiff(names(left), names(right))) {
    emit(id, left[[id]]$name, "missing", before = left[[id]])
  }
  fields_by_key <- function(test) {
    # Number repeated labels separately; unique field reordering is not a change.
    base <- vapply(test$fields, function(f) paste(f$section, f$label, sep = " / "), "")
    occurrence <- ave(seq_along(base), base, FUN = seq_along)
    setNames(test$fields, paste0(base, " [", occurrence, "]"))
  }
  for (id in intersect(names(left), names(right))) {
    a <- left[[id]]; b <- right[[id]]
    for (field in c("name", "number", "source_url")) {
      if (!identical(a[[field]], b[[field]])) {
        emit(id, b$name, "modified", field, a[[field]], b[[field]])
      }
    }
    af <- fields_by_key(a); bf <- fields_by_key(b)
    for (field in union(names(af), names(bf))) {
      if (!identical(af[[field]], bf[[field]])) {
        emit(id, b$name, "modified", field, af[[field]], bf[[field]])
      }
    }
  }
  events
}

history_next <- function(manifest, previous, current) {
  if (is.null(manifest)) manifest <- list(schema_version = "0.1", runs = list(), absent = list())
  if (is.null(previous)) return(list(events = list(), absent = list(), baseline = TRUE))
  if (!identical(previous$schema_version, current$schema_version)) {
    stop("Schema changed; baseline migration requires review")
  }
  if (!identical(previous$collector_version, current$collector_version)) {
    stop("Collector version changed; baseline migration requires review")
  }
  events <- catalog_diff(previous, current)
  # Carry absent tests across snapshots so removals are confirmed on run two.
  absent <- manifest$absent
  if (is.null(absent)) absent <- list()
  current_ids <- vapply(current$tests, `[[`, "", "id")
  for (id in intersect(names(absent), current_ids)) {
    test <- current$tests[[match(id, current_ids)]]
    events <- Filter(function(e) !(e$test_id == id && e$type == "added"), events)
    events[[length(events) + 1L]] <- list(test_id = id, name = test$name,
      type = "reappeared", field = NULL, before = absent[[id]]$test, after = test)
    # Include edits made while a test was absent, not merely its reappearance.
    events <- c(events, catalog_diff(list(tests = list(absent[[id]]$test)), list(tests = list(test))))
    absent[[id]] <- NULL
  }
  for (id in names(absent)) {
    absent[[id]]$count <- absent[[id]]$count + 1L
    if (absent[[id]]$count == 2L) {
      events[[length(events) + 1L]] <- list(test_id = id, name = absent[[id]]$test$name,
        type = "removed", field = NULL, before = absent[[id]]$test, after = NULL)
    }
  }
  for (e in events) if (e$type == "missing") {
    absent[[e$test_id]] <- list(count = 1L, test = e$before)
  }
  list(events = events, absent = absent, baseline = FALSE)
}

history_work_root <- function(start = getwd()) {
  start <- normalizePath(start, winslash = "/", mustWork = TRUE)
  # Connect content items use their own working files and share remote pins.
  if (history_store() == "connect") return(start)
  candidate <- start
  repeat {
    description <- file.path(candidate, "DESCRIPTION")
    if (file.exists(description) && file.exists(file.path(candidate, "scripts", "build-deploy.R"))) {
      package <- tryCatch(read.dcf(description, fields = "Package")[[1L]],
                          error = function(e) "")
      if (identical(package, "olsdexport")) return(candidate)
    }
    parent <- dirname(candidate)
    if (identical(parent, candidate)) return(start)
    candidate <- parent
  }
}

history_path <- function(variable, default) {
  path <- path.expand(Sys.getenv(variable, default))
  if (!nzchar(path)) stop(variable, " must not be empty")
  absolute <- startsWith(path, "/") || startsWith(path, "\\\\") ||
    grepl("^[A-Za-z]:[/\\\\]", path)
  if (absolute) path else file.path(history_work_root(), path)
}

history_board <- function() {
  history_log("CONFIG", paste("diagnostics=", history_diagnostics_version,
    "; OLSD_STORE present=", nzchar(Sys.getenv("OLSD_STORE")),
    "; CONNECT_SERVER present=", nzchar(Sys.getenv("CONNECT_SERVER")),
    "; CONNECT_API_KEY present=", nzchar(Sys.getenv("CONNECT_API_KEY")), sep = ""))
  mode <- history_store()
  if (mode == "connect") {
    missing <- c("CONNECT_SERVER", "CONNECT_API_KEY")[!nzchar(Sys.getenv(c("CONNECT_SERVER", "CONNECT_API_KEY")))]
    if (length(missing)) stop("Missing Connect configuration: ", paste(missing, collapse = ", "), call. = FALSE)
    server <- tryCatch(httr2::url_parse(Sys.getenv("CONNECT_SERVER")),
      error = function(e) stop("CONNECT_SERVER must be a valid server URL", call. = FALSE))
    if (!server$scheme %in% c("http", "https") || is.null(server$hostname) || !nzchar(server$hostname) ||
        length(server$username) || length(server$password) || length(server$query) || length(server$fragment)) {
      stop("CONNECT_SERVER must be a server URL without credentials, query parameters, or a fragment", call. = FALSE)
    }
    history_log("BOARD", paste("Connecting to", history_safe_url(Sys.getenv("CONNECT_SERVER"))))
    board <- tryCatch(pins::board_connect(auth = "envvar", use_cache_on_failure = FALSE), error = function(e) {
      detail <- history_redact(paste("Connect API connection failed before collection:", conditionMessage(e)))
      history_log("BOARD_FAILED", detail)
      stop(detail, call. = FALSE)
    })
    history_log("BOARD_OK", paste("Authenticated account:", board$account))
    board
  } else {
    # History is explicit in immutable run pins. Unversioned local pointers also
    # avoid ambiguous latest-version ordering for multiple writes in one second.
    path <- history_path("OLSD_BOARD_PATH", "outputs/board")
    history_log("BOARD", paste("Using local folder", path))
    pins::board_folder(path, versioned = FALSE)
  }
}

history_name <- function(suffix) paste0(Sys.getenv("OLSD_PIN_PREFIX", "olsd"), "-", suffix)

history_manifest <- function(board) {
  name <- history_name("index")
  if (!pins::pin_exists(board, name)) return(NULL)
  pins::pin_read(board, name)
}

history_snapshot <- function(board, run) {
  paths <- pins::pin_download(board, run$pin)
  path <- paths[basename(paths) == "snapshot.json"]
  if (length(path) != 1L) stop("Snapshot artifact missing or ambiguous")
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

history_collect <- function(board = history_board(), fetch = menu_get,
                            pause = as.numeric(Sys.getenv("OLSD_REQUEST_PAUSE", "0.25")),
                            allow_large_drop = FALSE, source_mode = "live", source_window = NULL) {
  if (!source_mode %in% c("live", "archive")) stop("Unknown source mode")
  if (source_mode == "archive" && is.null(source_window)) stop("Archive capture window is required")
  if (!is.finite(pause) || pause < 0 || (source_mode == "live" && pause < 0.1)) {
    stop("Request pause must be nonnegative and at least 0.1 seconds for live collection")
  }
  # Deployment must also serialize this content across workers/hosts.
  lock <- history_path("OLSD_LOCK_PATH", "outputs/collector.lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(lock, showWarnings = FALSE)) stop("Collector lock exists: ", lock)
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  run_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-",
                   paste(sample(c(letters, 0:9), 8, replace = TRUE), collapse = ""))
  writeLines(c(paste("run", run_id), paste("pid", Sys.getpid()),
               paste("host", Sys.info()[["nodename"]])), file.path(lock, "owner.txt"))
  started <- utc_now()
  status <- list(id = run_id, started_at = started, status = "running")
  work <- file.path(history_path("OLSD_OUTPUT_PATH", "outputs/runs"), run_id)
  dir.create(file.path(work, "source"), recursive = TRUE)
  journal <- file.path(work, "run-log.jsonl")
  checkpoint <- "START"
  current_test <- NULL
  collected <- 0L
  storage <- NULL
  board_ready <- FALSE
  every <- suppressWarnings(as.integer(Sys.getenv("OLSD_PROGRESS_EVERY", "25")))
  if (is.na(every) || every < 1L) stop("OLSD_PROGRESS_EVERY must be a positive integer")
  step <- function(stage, detail) {
    checkpoint <<- stage
    history_log(stage, detail, run_id = run_id, journal = journal)
  }
  tryCatch({
    step("START", paste("diagnostics=", history_diagnostics_version, "; source mode=", source_mode, sep = ""))
    step("BOARD", "Opening the configured storage board")
    force(board)
    board_ready <- TRUE
    step("PREFLIGHT", "Verifying storage write/read before contacting the test menu")
    storage <- history_preflight(board)
    status$stage <- "collecting"
    status$storage <- storage
    pins::pin_write(board, status, name = history_name("last-attempt"), type = "rds")
    step("BASELINE", paste("Reading", history_name("index")))
    manifest <- history_manifest(board)
    previous <- if (length(manifest$runs)) history_snapshot(board, tail(manifest$runs, 1)[[1]]) else NULL
    step("INVENTORY", paste("Discovering tests at", paste0(menu_base, "/api/CHOP/TestSearch/GetAll")))
    inventory <- menu_inventory(fetch, pause = pause)
    step("INVENTORY_OK", paste(inventory$count, "tests verified across", inventory$search_pages, "search pages"))
    writeLines(inventory$raw_index, file.path(work, "source", "inventory.json"))
    for (i in seq_along(inventory$raw_search)) {
      writeLines(inventory$raw_search[[i]], file.path(work, "source", paste0("search-", i, ".json")))
    }
    if (!is.null(previous) && inventory$count < 0.9 * previous$inventory_count && !allow_large_drop) {
      stop("Inventory dropped by more than 10%; review required before acceptance")
    }
    tests <- vector("list", inventory$count)
    for (i in seq_along(inventory$tests)) {
      test <- inventory$tests[[i]]
      current_test <- as.character(test$testId)
      if ((i - 1L) %% every == 0L) {
        step("DETAILS", paste("Fetching test", i, "of", inventory$count,
          paste0(menu_base, "/chop/Tests/", current_test)))
      }
      Sys.sleep(pause)
      html <- fetch(paste0("/chop/Tests/", test$testId))
      writeLines(html, file.path(work, "source", paste0(test$testId, ".html")))
      tests[[i]] <- menu_detail(html, test)
      collected <- i
      if (i %% every == 0L || i == inventory$count) {
        step("DETAILS", sprintf("Collected %d/%d (%.1f%%); elapsed %.1f minutes", i, inventory$count,
          100 * i / inventory$count, as.numeric(difftime(Sys.time(), as.POSIXct(started, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "mins"))))
      }
    }
    current_test <- NULL
    step("INVENTORY_FINAL", "Rechecking inventory after collection")
    final_text <- fetch("/api/CHOP/TestSearch/GetAll")
    writeLines(final_text, file.path(work, "source", "inventory-end.json"))
    final_ids <- vapply(menu_decode(final_text)$Tests, function(t) as.character(t$testId), "")
    initial_ids <- vapply(inventory$tests, function(t) as.character(t$testId), "")
    if (anyDuplicated(final_ids) || !setequal(initial_ids, final_ids)) {
      stop("Inventory changed during detail collection; retry required")
    }
    if (source_mode == "live") source_window <- list(first = started, last = utc_now())
    snapshot <- list(schema_version = "0.1", collector_version = "0.1.0",
      purpose = "catalog_snapshot", complete = TRUE, run_id = run_id,
      collected_at = utc_now(), started_at = started,
      source_mode = source_mode, source_window = source_window,
      source_revision = Sys.getenv("OLSD_SOURCE_REVISION", "unknown"),
      inventory_count = inventory$count, search_total = inventory$search_total,
      search_pages = inventory$search_pages, collected_count = length(tests), tests = tests)
    # Round-trip JSON before comparing so R integer/numeric differences cannot
    # introduce false edits between freshly parsed and persisted snapshots.
    snapshot <- jsonlite::fromJSON(jsonlite::toJSON(snapshot, auto_unbox = TRUE,
      null = "null", na = "null"), simplifyVector = FALSE)
    next_state <- history_next(manifest, previous, snapshot)
    step("EXPORT", "Writing JSON, Excel, differences, and source archive")
    menu_write_exports(snapshot, work)
    jsonlite::write_json(next_state$events, file.path(work, "changes.json"),
      auto_unbox = TRUE, pretty = TRUE, null = "null")
    source_files <- list.files(file.path(work, "source"), full.names = FALSE)
    original <- getwd()
    tryCatch({
      setwd(file.path(work, "source"))
      utils::tar("../source.tar.gz", files = source_files, compression = "gzip", tar = "internal")
    }, finally = setwd(original))
    run_pin <- history_name(paste0("run-", run_id))
    jsonlite::write_json(storage, file.path(work, "storage.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
    step("UPLOAD", paste("Uploading artifacts to", run_pin, "(display title: OLSD run", paste0(run_id, ")")))
    # Freeze the artifact copy; the live journal continues through verification.
    file.copy(journal, file.path(work, "collection-log.jsonl"), overwrite = TRUE)
    paths <- file.path(work, c("snapshot.json", "snapshot.xlsx", "changes.json", "source.tar.gz", "storage.json", "collection-log.jsonl"))
    pins::pin_upload(board, paths, name = run_pin, title = paste("OLSD run", run_id))
    step("VERIFY", paste("Downloading and checking uploaded artifacts from", run_pin))
    uploaded <- pins::pin_download(board, run_pin)
    if (!setequal(basename(paths), basename(uploaded))) stop("Uploaded artifact verification failed")
    for (path in paths) {
      if (unname(tools::md5sum(path)) != unname(tools::md5sum(uploaded[basename(uploaded) == basename(path)]))) {
        stop("Uploaded artifact checksum mismatch")
      }
    }
    run <- list(id = run_id, pin = run_pin, collected_at = snapshot$collected_at,
      count = inventory$count, baseline = next_state$baseline,
      event_count = length(next_state$events), events = next_state$events, storage = storage)
    run_location <- history_pin_info(board, run_pin)
    step("UPLOAD_OK", paste("Published pin=", run_location$name, "; URL=", run_location$url,
      "; content GUID=", run_location$content_guid, sep = ""))
    if (is.null(manifest)) manifest <- list(schema_version = "0.1", runs = list())
    manifest$runs[[length(manifest$runs) + 1L]] <- run
    manifest$absent <- next_state$absent
    step("INDEX", paste("Publishing accepted history to", history_name("index")))
    pins::pin_write(board, manifest, name = history_name("index"), type = "rds")
    saved <- history_manifest(board)
    if (!identical(tail(saved$runs, 1)[[1]]$id, run_id)) stop("Accepted index readback did not contain the new run")
    index_location <- history_pin_info(board, history_name("index"))
    step("INDEX_OK", paste("Readback verified; pin=", index_location$name, "; URL=", index_location$url,
      "; content GUID=", index_location$content_guid, sep = ""))
    status <- list(id = run_id, started_at = started, finished_at = utc_now(), status = "accepted",
                   stage = "complete", baseline = run$baseline, count = run$count,
                   event_count = run$event_count, storage = storage, published = list(run = run_location, index = index_location))
    step("STATUS", paste("Saving accepted status to", history_name("last-attempt")))
    pins::pin_write(board, status, name = history_name("last-attempt"), type = "rds")
    saved_status <- pins::pin_read(board, history_name("last-attempt"))
    if (!identical(saved_status$id, run_id) || !identical(saved_status$status, "accepted")) {
      stop("Accepted status readback mismatch")
    }
    step("ACCEPTED", paste("Saved", run$count, "tests;", run$event_count, "change events; storage=", storage$mode))
    status
  }, error = function(e) {
    status <- list(id = run_id, started_at = started, finished_at = utc_now(),
                   status = "failed", stage = if (!is.null(e$olsd_stage)) e$olsd_stage else checkpoint, current_test = current_test,
                   collected_count = collected, storage = storage, error = history_redact(conditionMessage(e)))
    try(history_log("FAILED", paste("Last stage:", status$stage, "; test:", current_test,
      "; collected:", collected, ";", status$error), run_id, journal), silent = TRUE)
    # If storage itself is unavailable, preserve the failure locally as well.
    jsonlite::write_json(status, file.path(work, "failure.json"), auto_unbox = TRUE, pretty = TRUE)
    if (board_ready) tryCatch(pins::pin_write(board, status, name = history_name("last-attempt"), type = "rds"),
      error = function(storage_error) history_log("FAILURE_STATUS_UNSAVED", history_redact(conditionMessage(storage_error)), run_id))
    stop(status$error, call. = FALSE)
  })
}
