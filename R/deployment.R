# Build-time helpers only; these are not shipped in either Connect content item.
deployment_repositories <- function(lockfile) {
  lock <- jsonlite::read_json(lockfile)
  records <- lock[["R"]][["Repositories"]]
  if (!length(records)) stop("renv.lock has no named R repositories. Set a reachable CRAN mirror and run renv::snapshot().", call. = FALSE)
  valid <- vapply(records, function(record) {
    name <- record[["Name"]]; url <- record[["URL"]]
    is.character(name) && length(name) == 1L && !is.na(name) && nzchar(name) &&
      is.character(url) && length(url) == 1L && !is.na(url) && grepl("^https?://[^[:space:]]+$", url)
  }, TRUE)
  if (!all(valid)) stop("renv.lock contains an unnamed or invalid repository. Record a named, reachable repository before generating manifests.", call. = FALSE)
  repos <- setNames(vapply(records, `[[`, "", "URL"), vapply(records, `[[`, "", "Name"))
  if (anyDuplicated(names(repos))) stop("renv.lock has duplicate repository names", call. = FALSE)
  repos
}

deployment_check_manifest <- function(file) {
  manifest <- jsonlite::read_json(file)
  packages <- manifest[["packages"]]
  if (!length(packages)) stop("Generated manifest contains no R packages", call. = FALSE)
  invalid <- names(packages)[vapply(packages, function(package) {
    source <- package[["Source"]]
    if (!is.null(source) && tolower(source) %in% c("github", "gitlab", "bitbucket", "source", "local")) return(FALSE)
    repo <- package[["Repository"]]
    !is.character(repo) || length(repo) != 1L || is.na(repo) || !grepl("^https?://[^[:space:]]+$", repo)
  }, TRUE)]
  if (length(invalid)) {
    stop("Generated manifest has missing/invalid repository URLs for: ", paste(invalid, collapse = ", "),
      ". rsconnect may have been unable to read the source PACKAGES index. Check the repositories in renv.lock; do not deploy this manifest.", call. = FALSE)
  }
  invisible(manifest)
}

deployment_build <- function(root = ".", index_reader = utils::available.packages,
                             writer = rsconnect::writeManifest) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  repos <- deployment_repositories(file.path(root, "renv.lock"))
  previous <- options(repos = repos)
  on.exit(options(previous), add = TRUE)
  message("Preparing Connect manifests with R ", getRversion(), "; rsconnect ", utils::packageVersion("rsconnect"))
  message("Checking source package indexes for named repositories: ", paste(names(repos), collapse = ", "))
  index <- index_reader(repos = repos, type = "source")
  if (!is.matrix(index) || !nrow(index)) {
    stop("No source package index could be read. Manifest generation stopped before replacing deployment files. Use a reachable named repository in renv.lock (binary package downloads alone do not verify source-index access).", call. = FALSE)
  }
  staging <- tempfile("olsd-deployment-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  for (kind in c("app", "collector")) {
    target <- file.path(staging, kind)
    dir.create(file.path(target, "R"), recursive = TRUE)
    entry <- if (kind == "app") "app.R" else "collector.Rmd"
    files <- c(entry, "R/source.R", "R/history.R", "renv.lock", "COPYRIGHT")
    for (name in files) {
      if (!file.copy(file.path(root, name), file.path(target, name), overwrite = TRUE)) {
        stop("Could not stage deployment file: ", name, call. = FALSE)
      }
    }
    writer(appDir = target, appFiles = files, appPrimaryDoc = entry,
      appMode = if (kind == "app") "shiny" else "rmd-static", quarto = FALSE)
    deployment_check_manifest(file.path(target, "manifest.json"))
  }
  # Keep both existing content directories intact until both manifests validate.
  for (kind in c("app", "collector")) {
    target <- file.path(root, "deploy", kind)
    dir.create(file.path(target, "R"), recursive = TRUE, showWarnings = FALSE)
    source <- file.path(staging, kind)
    files <- list.files(source, recursive = TRUE, all.files = TRUE)
    for (name in files) {
      if (!file.copy(file.path(source, name), file.path(target, name), overwrite = TRUE)) {
        stop("Could not update deployment file: ", name, call. = FALSE)
      }
    }
    message("Verified manifest and synchronized deploy/", kind)
  }
  invisible(TRUE)
}
