# olsd-export

Automated export and change tracking for the [CHOP laboratory test menu](https://www.testmenu.com/chop).

The project captures published test details, preserves historical snapshots, and makes changes easy to review over time.

## Status

The first R implementation includes inventory verification, detail collection, JSON/Excel exports, pins history, field-level comparisons, a Shiny viewer, and a scheduled R Markdown report. Institution-specific deployment and email delivery still require validation on your Posit Connect installation.

See [development and deployment instructions](docs/deployment.md) and the approved [project specification](SPEC.md).

## Workflow

1. Collect all publicly discoverable test details daily, including send-out tests.
2. Export structured JSON for comparison and Excel for review.
3. Store accepted snapshots and run history using pins on institution-managed Posit Connect.
4. Compare accepted snapshots and report added, modified, missing, and removed tests with field-level before/after values.
5. Send email notifications and provide an R Shiny application for reviewing test and change history.

PDF link labels and destinations are included. PDF files and their contents are not collected. Incomplete collection runs must not replace the accepted baseline or produce false removal reports.

## Technology

- **R** with `httr2` and `rvest`/`xml2` for direct HTTP collection and HTML parsing.
- **JSON** as the authoritative export and basis for structured comparisons.
- **pins** for persistent snapshots and manifests.
- **R Markdown** for scheduled collection and reporting on Posit Connect.
- **Shiny** for browsing current details and historical changes.
- **renv** lockfile for R dependencies.

The menu's public data endpoint provides stable test IDs, and its detail pages contain ordinary HTML. Collection uses direct HTTP requests; no browser automation is needed. Inventory acceptance requires agreement between the complete index and paginated search, plus checks against public category/status lists.

## Running locally

Install/restore the packages and activate the project library as described in the [setup guide](docs/deployment.md). From an R session at the repository root:

```r
renv::load()
testthat::test_dir("tests/testthat")
source("scripts/sample-export.R") # Complete inventory check; seven-test sample export
source("scripts/collect.R")       # Complete catalog collection; may take many minutes
shiny::runApp(".")
```

Local defaults retain data in the ignored `outputs/` directory. Public configuration examples are in [.env.example](.env.example). The project does not automatically load that file.

Edit the root `app.R` and use `shiny::runApp(".")` for local development. `deploy/app/app.R` is a generated copy for Connect; inside a complete checkout it shares the root app's local snapshot folder. See [local app entry points and troubleshooting](docs/deployment.md#which-app-should-i-run-locally).

See [SPEC.md](SPEC.md) for scope, architecture, acceptance criteria, and outstanding deployment decisions.

Generated exports, captured source pages, local credentials, and runtime caches belong outside version control. Keep small, intentional test fixtures in a dedicated fixtures directory when tests are introduced.

## Deployment path

Development source is published in this public repository. The user pulls the selected changes and pushes them to an institution-controlled private GitHub repository. Institution-managed Posit Connect then deploys the scheduled report and Shiny application from that private repository using GitHub-backed deployment.

Run `source("scripts/build-deploy.R")` with the project library loaded to synchronize the deployment directories and call `rsconnect::writeManifest()` for each content item. Commit both `deploy/app/manifest.json` and `deploy/collector/manifest.json` with the generated source files. See [manifest generation](docs/deployment.md#generate-the-connect-deployment-manifests) for the exact calls and Connect directory selections.

Institution-specific configuration and credentials are supplied through supported deployment settings or private configuration. Historical snapshots remain in pins across source updates and redeployments. Public examples will use placeholders; automatic public-to-private mirroring is outside the initial scope.

For storage problems, set `OLSD_PREFLIGHT_ONLY=true` on the collector and render a [storage-only diagnostic report](docs/deployment.md#diagnose-storage-and-request-failures-before-a-full-collection). It verifies a small pin before any test-menu requests and shows the destination, account, and pin URLs. Return the flag to `false` for normal collection.

## Copyright

Copyright © 2026 amromeo. See [COPYRIGHT](COPYRIGHT). An open-source license has not been selected.
