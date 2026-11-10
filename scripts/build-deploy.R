# Run from repository root after changing application code or dependencies.
# Generated, self-contained roots let Connect deploy both content types from Git.
for (kind in c("app", "collector")) {
  target <- file.path("deploy", kind)
  dir.create(file.path(target, "R"), recursive = TRUE, showWarnings = FALSE)
  file.copy(c("R/source.R", "R/history.R"), file.path(target, "R"), overwrite = TRUE)
  file.copy("renv.lock", target, overwrite = TRUE)
  file.copy("COPYRIGHT", target, overwrite = TRUE)
  entry <- if (kind == "app") "app.R" else "collector.Rmd"
  file.copy(entry, target, overwrite = TRUE)
  rsconnect::writeManifest(appDir = target,
    appFiles = c(entry, "R/source.R", "R/history.R", "renv.lock", "COPYRIGHT"),
    appPrimaryDoc = entry, appMode = if (kind == "app") "shiny" else "rmd-static",
    quarto = FALSE)
}
