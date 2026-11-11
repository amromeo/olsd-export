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

### Which app should I run locally?

The root `app.R` is the source application. `deploy/app/app.R` is its generated deployment copy. Edit the root files and regenerate deployment copies with `scripts/build-deploy.R`.

For local development, launch from the repository root:

```r
shiny::runApp(".")
```

The generated app can also be launched with `shiny::runApp("deploy/app")`. In a complete repository checkout, relative local board, output, and lock paths resolve from the repository root, so both entry points use the same `outputs/board`. A standalone deployment directory uses its own working directory. Connect-backed storage continues to use the configured shared pins board.

If a collector succeeded but the app shows no snapshots, check `OLSD_STORE`, `OLSD_BOARD_PATH`, and `OLSD_PIN_PREFIX` in the R session. For an existing baseline stored elsewhere, set its absolute folder before launching; from the repository root, for example:

```r
Sys.setenv(OLSD_BOARD_PATH = normalizePath("outputs/board", winslash = "/", mustWork = TRUE))
shiny::runApp("deploy/app")
```

An accepted baseline does not need to be collected again to change which local app entry point you use.

## Generate the Connect deployment manifests

Git-backed deployment uses `rsconnect::writeManifest()`. This project has two content items, each with its own manifest:

| Content | Connect content directory | Manifest to commit |
| --- | --- | --- |
| Shiny history viewer | `deploy/app` | `deploy/app/manifest.json` |
| Scheduled collection report | `deploy/collector` | `deploy/collector/manifest.json` |

Both manifests are already committed. To regenerate them after changing code or dependencies, run this from an R session at the repository root:

```r
renv::load()
source("scripts/build-deploy.R")
```

The helper first copies the current entry points, shared R code, copyright notice, and lockfile into the two deployment directories. It then runs these `rsconnect::writeManifest()` calls:

```r
rsconnect::writeManifest(
  appDir = "deploy/app",
  appFiles = c("app.R", "R/source.R", "R/history.R", "renv.lock", "COPYRIGHT"),
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  quarto = FALSE
)

rsconnect::writeManifest(
  appDir = "deploy/collector",
  appFiles = c("collector.Rmd", "R/source.R", "R/history.R", "renv.lock", "COPYRIGHT"),
  appPrimaryDoc = "collector.Rmd",
  appMode = "rmd-static",
  quarto = FALSE
)
```

Use the helper to keep deployment copies synchronized with root source files before generating their manifests. Commit the generated files and manifests, then push them to the private GitHub repository used by Connect. Manifest generation prepares files locally; Connect performs deployment from Git after those files are pushed.

Generate manifests using an R runtime supported by your Connect installation. If you need to change the R or package versions recorded in `renv.lock`, restore/test the intended environment and update the lockfile before regenerating the deployment directories and manifests.

## Public to private GitHub

1. Develop and test in the public repository.
2. After editing source files or dependency versions, [regenerate both manifests](#generate-the-connect-deployment-manifests) with `renv::load(); source("scripts/build-deploy.R")` in R at the repository root. Commit both generated `deploy/` directories, manifests, and the lockfile along with source changes. The generated copies must match the root source files.
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

Connect may already inject `CONNECT_SERVER` and an ephemeral `CONNECT_API_KEY` for the content owner. Reuse those when available and suitable; set explicit values only when the institution disables that feature or requires another identity. Diagnostics record presence and the authenticated account, never the key value. See [Connect runtime variables](https://docs.posit.co/connect/user/content-settings/#environment-variables).

## Diagnose storage and request failures before a full collection

For a quick check on Connect:

1. Transfer the updated source and generated deployment files to private GitHub, then redeploy the collector content from that revision.
2. Set `OLSD_STORE=connect` and `OLSD_PREFLIGHT_ONLY=true` on the **collector** content. Values should not contain literal quotation marks. Render the report with the new code and settings.
3. Look for `storage-diagnostics-1` and `execution=preflight-only` near the beginning of the render log. This confirms that the new diagnostics code is executing. The check connects to the configured server, writes a small pin, reads it back, and reports its published URL, content GUID, account, and full name. It does not contact `testmenu.com`, run the collector, or modify the accepted baseline.
4. The diagnostic pin has internal name `<prefix>-diagnostics` and display title **OLSD storage diagnostics**. The HTML report lists its exact location and whether index/status pins already exist. A successful probe proves small-pin creation and readback; a later large upload or index update can still fail and has separate checkpoints.
5. After the preflight passes, set `OLSD_PREFLIGHT_ONLY=false` and run the full collector. Full collections also run the storage check before requesting any test pages.

Locally, `source("scripts/preflight.R")` runs the same storage-only check using the current configuration. The report also accepts the R Markdown parameter `preflight_only: true`. Preflight reports suppress scheduled email; restore normal collection mode after troubleshooting.

Progress is sent to the render console even though the setup chunk is hidden from the document. Expect these stages:

| Log marker | Meaning / useful next check |
| --- | --- |
| `CONFIG`, `BOARD`, `BOARD_OK` | Selected configuration, server, and authenticated account; missing/invalid configuration fails before collection. A Connect API timeout here concerns access from the runner to the Connect server. |
| `PREFLIGHT_WRITE`, `PREFLIGHT_READ`, `PREFLIGHT_OK` | A small pin is created and read back. Inspect permissions, the pin prefix, or runner-to-Connect networking if this fails. |
| `SOURCE_HTTP`, `SOURCE_HTTP_OK` | The URL of an inventory/search request and its HTTP outcome. |
| `DETAILS` | Test count, percentage, current test URL at the start of each batch, and elapsed collection time. Defaults to a batch of 25 tests. |
| `SOURCE_HTTP_RETRY`, `SOURCE_HTTP_FAILED` | Bounded retry or final failure of an exact test-menu URL. A timeout here concerns source access, not pin publication. |
| `EXPORT`, `UPLOAD`, `VERIFY` | Local artifact generation, snapshot upload, and verification by downloading and comparing checksums. |
| `INDEX`, `INDEX_OK`, `STATUS`, `ACCEPTED` | Index publication and readback, final status publication/readback, and completion. |
| `FAILED` | Last stage, current test ID, successful detail count, and a redacted error. |

For finer tracing, set `OLSD_PROGRESS_EVERY=1` and/or `OLSD_HTTP_TRACE=true` while troubleshooting. Source requests retain a 60-second per-request timeout; transport errors and transient HTTP responses receive up to three total attempts, with retry messages. Repeated zero-byte timeouts may require the institution to check DNS, proxy/firewall policy, or outbound access to the exact logged source host. Increasing a timeout does not establish that a destination is reachable.

The report lists storage mode, board class, server/account or local directory, pin prefix, variable presence, and actual pin URLs/GUIDs. The snapshot pin's **display title** is `OLSD run <run ID>`; its internal name is `<prefix>-run-<run ID>`, so a UI search for the internal name alone may be misleading. Check the report's account and direct URLs, including content-type/owner filters in Connect.

Local working files include `run-log.jsonl` and a failure record with stage/test context. Successful run pins also contain `storage.json` and a frozen `collection-log.jsonl` covering collection through upload start. The live render log continues through upload, index, and status verification. A running last-attempt pin is saved after preflight; preflight-only checks do not replace collection status.

Connect requires `OLSD_STORE=connect` when its documented runtime marker identifies the process as Connect. Invalid storage values fail explicitly instead of falling back to local files. Variables must be set on the collector as well as the Shiny content; each content item has its own runtime settings.

Connect can continue serving the previous successful HTML report after a failed render. Confirm the diagnostics marker, execution mode, run ID, and latest job outcome in the **render log** before treating a visible report as the new result.

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
