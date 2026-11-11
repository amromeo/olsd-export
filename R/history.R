utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

display_time <- function(value) {
  time <- as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  format(time, "%Y-%m-%d %H:%M:%S %Z", tz = Sys.getenv("OLSD_DISPLAY_TZ", "America/New_York"))
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
  if (identical(Sys.getenv("OLSD_STORE", "local"), "connect")) return(start)
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
  if (identical(Sys.getenv("OLSD_STORE", "local"), "connect")) {
    pins::board_connect(auth = "envvar", use_cache_on_failure = FALSE)
  } else {
    # History is explicit in immutable run pins. Unversioned local pointers also
    # avoid ambiguous latest-version ordering for multiple writes in one second.
    pins::board_folder(history_path("OLSD_BOARD_PATH", "outputs/board"), versioned = FALSE)
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
  tryCatch({
    manifest <- history_manifest(board)
    previous <- if (length(manifest$runs)) history_snapshot(board, tail(manifest$runs, 1)[[1]]) else NULL
    inventory <- menu_inventory(fetch, pause = pause)
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
      Sys.sleep(pause)
      html <- fetch(paste0("/chop/Tests/", test$testId))
      writeLines(html, file.path(work, "source", paste0(test$testId, ".html")))
      tests[[i]] <- menu_detail(html, test)
      if (i %% 100 == 0) message("Collected ", i, "/", inventory$count)
    }
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
    paths <- file.path(work, c("snapshot.json", "snapshot.xlsx", "changes.json", "source.tar.gz"))
    pins::pin_upload(board, paths, name = run_pin, title = paste("OLSD run", run_id))
    uploaded <- pins::pin_download(board, run_pin)
    if (!setequal(basename(paths), basename(uploaded))) stop("Uploaded artifact verification failed")
    for (path in paths) {
      if (unname(tools::md5sum(path)) != unname(tools::md5sum(uploaded[basename(uploaded) == basename(path)]))) {
        stop("Uploaded artifact checksum mismatch")
      }
    }
    run <- list(id = run_id, pin = run_pin, collected_at = snapshot$collected_at,
      count = inventory$count, baseline = next_state$baseline,
      event_count = length(next_state$events), events = next_state$events)
    if (is.null(manifest)) manifest <- list(schema_version = "0.1", runs = list())
    manifest$runs[[length(manifest$runs) + 1L]] <- run
    manifest$absent <- next_state$absent
    pins::pin_write(board, manifest, name = history_name("index"), type = "rds")
    status <- list(id = run_id, started_at = started, finished_at = utc_now(), status = "accepted",
                   baseline = run$baseline, count = run$count, event_count = run$event_count)
    pins::pin_write(board, status, name = history_name("last-attempt"), type = "rds")
    status
  }, error = function(e) {
    status <- list(id = run_id, started_at = started, finished_at = utc_now(),
                   status = "failed", error = conditionMessage(e))
    # If storage itself is unavailable, preserve the failure locally as well.
    jsonlite::write_json(status, file.path(work, "failure.json"), auto_unbox = TRUE, pretty = TRUE)
    tryCatch(pins::pin_write(board, status, name = history_name("last-attempt"), type = "rds"),
             error = function(storage_error) message("Could not persist failure status: ", conditionMessage(storage_error)))
    stop(e)
  })
}
