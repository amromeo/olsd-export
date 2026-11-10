# Development and deployment

## Local development

Use R 4.1 or later; the initial lockfile records the exact runtime used for validation. The institution's supported R version still needs verification before deployment. From the repository root:

```r
install.packages("renv", repos = "https://cloud.r-project.org")
renv::restore()
```

For an initial installation without the lockfile, run `Rscript scripts/install.R`. Run all subsequent commands from the repository root and activate the restored library, for example with `renv::load()` in R. The project has no automatic `.Rprofile` activation yet.

```r
renv::load()
testthat::test_dir("tests/testthat")
source("scripts/sample-export.R")
source("scripts/collect.R")
shiny::runApp(".")
```

The sample script verifies the complete inventory but exports seven representative tests, explicitly marked incomplete. The collector exports the entire inventory and accepts it only after successful collection. A full run can take many minutes; progress is logged every 100 tests. Keep the configured request pause at least 0.1 seconds. PDF contents and linked external test catalogs are never fetched by the collector.

Defaults use a local pins board in `outputs/board`, with source captures and exports in `outputs/runs`. These directories are ignored by Git. `.env.example` documents configuration; it is not loaded automatically. A private `.Renviron` can configure local R sessions.

## Public to private GitHub

1. Develop and test in the public repository.
2. After editing source files or dependency versions, run `renv::load(); source("scripts/build-deploy.R")` in R at the repository root. Commit both generated `deploy/` directories, manifests, and the lockfile along with source changes. The generated copies must match the root source files.
3. Pull the public revision and push it to the institution's private repository using your usual transfer process.
4. Configure two Git-backed Connect content items from the private repository: `deploy/app` for Shiny and `deploy/collector` for the scheduled report. Each directory is self-contained; Connect requires no access to the public repository at runtime.

The generated directories contain deployment copies of shared code to support Connect installations that bundle only the selected content directory. Edit root source files and regenerate; do not edit generated copies independently. Confirm the installed Connect version supports the generated manifests and runtime/package versions.

## Connect configuration

Configure these values on both content items through Connect settings:

| Variable | Value |
| --- | --- |
| `OLSD_STORE` | `connect` |
| `CONNECT_SERVER` | Institution's Connect URL |
| `CONNECT_API_KEY` | Supported service identity API key, entered securely |
| `OLSD_PIN_PREFIX` | Same qualified prefix, e.g. `service-user/olsd` |

Configure `OLSD_APP_URL` on the collector to the actual Shiny application URL so emails link to the corresponding run. Set `OLSD_SOURCE_REVISION` to the transferred source revision where your workflow supports it; otherwise run metadata explicitly records `unknown`.

The collector identity needs permission to create and update pins; the Shiny identity needs read access to the same pins. Pin sharing and ownership must be verified on the institution's Connect instance. Sharing the Shiny app does not automatically share its pins. Keep API keys and institution-specific settings out of both source repositories.

Schedule the collector daily, with the chosen time and timezone (proposed: America/New_York). Enable scheduled email for the intended recipients. The R Markdown report suppresses scheduled email on unchanged runs; baseline and changed runs get a subject, summary, and app link. Configure Connect's render-failure notifications for the owner/operator. These platform features are documented in [Connect scheduling](https://docs.posit.co/connect/user/scheduling/) and [R Markdown email customization](https://docs.posit.co/connect/user/rmarkdown/#r-markdown-email-customization); verify support in the installed version.

Timestamps are stored in UTC. Reports and the Shiny viewer display America/New_York by default, with timezone labels; set `OLSD_DISPLAY_TZ` on both content items to change presentation. Set the Connect schedule's timezone separately.

Serialize collector execution: use one scheduled content item and do not overlap scheduled runs with manual renders or separate collectors sharing the same pins. The local directory lock guards processes sharing its filesystem; it is not a distributed lock across Connect hosts. Check the installation's scheduling/concurrency settings before enabling production collection. A hard process termination may leave `outputs/collector.lock`; confirm the prior process is gone before removing that directory. Do not remove a lock while a collector is running.

The browser app is read-only and refreshes from pins when opened or when **Refresh history** is selected. Code redeployment must leave pins intact.

## Acceptance on the institution's Connect instance

- Deploy both content items through private GitHub and confirm dependency restoration.
- Run a full collection, open the Shiny inventory, and download the corresponding JSON and Excel artifacts.
- Run again in a fresh process and confirm a no-change result or investigate every observed difference.
- Verify a scheduled baseline/change email links to the intended run, unchanged emails are suppressed, and failed renders alert the operator.
- Redeploy and confirm historical snapshots, run links, and the accepted baseline remain available.
- Verify pins visibility using the actual application identity and intended viewers.

No automatic emails are sent from local development by this code. Delivery uses Connect's configured scheduled-report mechanism. Email delivery receipts/retries are managed by Connect; the initial implementation has no separate delivery ledger and does not guarantee exactly-once delivery after a rendering or mail failure.

## Recovery and retention

Every accepted run has its own pin containing JSON, Excel, differences, and a compressed source archive. The index is updated only after uploaded artifacts are checked. Failed attempts retain their local artifacts and update the last-attempt status where storage remains available. A failure before index publication leaves the previous baseline intact; a failure after index publication is an operational failure and may leave a valid newly accepted snapshot available. Inspect the manifest and run ID before rerunning.

An inventory decline over 10% is rejected pending review. After investigating, an operator can call `history_collect(allow_large_drop = TRUE)` explicitly from a controlled R session; no automatic scheduled bypass is provided. Parser/schema changes require reviewing or migrating the baseline rather than silently accepting false source edits.

Retain all accepted snapshots and change records initially. Source archives are also retained initially; measure volume and agree on a retention policy before a long-running deployment. Local working artifacts are not automatically cleaned up yet and need storage monitoring/rotation. A pin uploaded before an interrupted index update may be unreferenced; inspect it before cleanup. Do not delete the index, historical run pins, or underlying backups as routine redeployment steps.

For reviewed extractor migrations, `scripts/reprocess.R path/to/source` reparses a complete captured source directory without contacting the website. Select a new empty board/pin prefix first; the script refuses to overwrite existing history. Reprocessed snapshots record `source_mode = archive` and the source-file capture window, distinguishing processing time from a live source check. Review the resulting baseline before changing production content to use it.
