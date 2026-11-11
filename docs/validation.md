# Validation notes

The initial development environment uses R 4.5.3. Dependencies are recorded in `renv.lock`. The institution's supported R version and fresh dependency restoration remain target-deployment checks.

## Source feasibility

On November 10, 2026, the public CHOP menu's GetAll index returned 1,554 unique test IDs. All IDs matched an independent traversal of 16 search-result pages. Public category and status lists introduced no additional test identities.

Detail pages expose their test fields in HTML. Desktop/mobile duplicate markup is explicitly handled, and unexpected layouts or data-binding placeholders within test details are rejected. No browser automation is required for collection.

The seven-test sample includes:

| Test ID | Test | Fields | Tables | Detail links |
| --- | --- | ---: | ---: | ---: |
| 785763 | (1,3)-Beta-D-Glucan (Fungitell) | 16 | 0 | 2 |
| 785260 | Cbc, Platelet With Differential | 17 | 12 | 0 |
| 786124 | Abnormal Coagulation Workup | 16 | 0 | 0 |
| 1224037 | Consult Surgical - from Outside Clients | 15 | 0 | 4 |
| 785113 | Chromosome analysis Skin/Other Solid Tissue | 15 | 0 | 0 |
| 1363450 | CYP2C19 | 21 | 0 | 1 |
| 786502 | Glucose | 15 | 2 | 1 |

Sample JSON and Excel files and captured source pages are retained locally under `outputs/feasibility/`, outside Git. The sample is explicitly marked incomplete and is not a production baseline.

## Complete catalog export

All 1,554 test pages were retrieved during the initial live crawl. The final extractor was then run against the retained pages, reconciling the initial inventory with a fresh end-of-collection index. The resulting accepted local snapshot contains 1,554 tests and 24,452 detail fields, with JSON, Excel, a zero-event baseline, and a compressed source archive. This reprocessing is explicitly marked `source_mode = archive`, with the original source capture window retained; it was not a second live crawl.

Full-catalog validation exposed leading whitespace in some source link destinations and two malformed destinations on test 864026. Leading whitespace is normalized. Destinations that cannot be resolved are preserved with `resolution_error = true` rather than discarded. The Excel export retains long cell values as ordered chunks in a `LongText` sheet when necessary.

Complete export artifacts are retained locally under `outputs/validated/`, outside Git. Production collection and Connect validation remain separate from this development baseline.

A second complete pass over the same retained source pages ran in a fresh R process, published another accepted snapshot through the local pins workflow, and produced zero change events across all 1,554 tests. This verifies repeatability against unchanged captured content, not a second live website crawl.

## Automated checks

Offline regression tests exercise complete inventory traversal and rejection of incomplete pagination, detail identity/layout checks, exclusion of mobile duplicates, tables and spans, PDF links, line-break normalization, scientific superscripts, field-level numerical changes, reordered fields, missing/removal confirmation, edited reappearance, schema migration rejection, real local pins round trips, baseline preservation after a detail failure, Excel long-text preservation, and Shiny detail/change/filter output.

The initial local suite passed 48 assertions with no failures, warnings, or skips. A GitHub Actions workflow is included for subsequent pushes; its remote result is distinct from these local checks.

Automated Chromium smoke tests opened the live Shiny process against a separate local sample board and verified test details, the empty change view, run history, test search, clinical tables, and a JSON download, without JavaScript errors. The scheduled R Markdown report rendered successfully against that sample board with collection disabled. These checks do not establish institution-side Connect deployment or actual email delivery.

The viewer was also checked against the complete catalog: archive provenance, search across the full inventory, and reference-table rendering passed without JavaScript errors. The scheduled report rendered successfully from the complete accepted snapshot.

## Local entry-point regression

Relative local storage paths originally depended on the process working directory. A collector run from the repository root could therefore save a valid baseline that `shiny::runApp("deploy/app")` could not see. Local storage, output, and lock paths now resolve from the repository root when running inside a complete checkout. Explicit absolute paths are preserved; isolated deployment directories remain self-contained, and Connect working paths stay within the content directory.

The updated suite passed 63 assertions with no failures, warnings, or skips, including root/generated-entry-point sharing, standalone paths, Windows drive/UNC paths, and Connect path isolation. An automated browser test launched the generated app with `shiny::runApp("deploy/app")` and displayed the existing root board's 1,554-test history without another collection. Both deployment directories and manifest checksums were regenerated and verified.

## Storage diagnostics and request timeouts

The collector now verifies a small diagnostic pin before requesting any test-menu pages, records its destination/account and published metadata, and emits timestamped checkpoints through the render console. The hidden setup chunk explicitly forwards messages. Accepted run and status writes are read back for verification; failures record stage, collected count, current test ID, and redacted errors. Invalid storage modes and missing Connect configuration fail before collection instead of using a local fallback on Connect.

Local tests cover probe write/read and baseline preservation, stopping before source requests when pin publication fails, credential redaction and safe URL handling, Connect configuration validation, hidden-chunk console messages, storage-only report generation without source HTTP calls, and three bounded transport attempts with an exact source URL in the final error. A real storage-only HTML report and an existing full-catalog report were also rendered locally. No additional live catalog crawl was needed.

These checks do not prove network access or permissions on the institution's Connect runner. The reported 60-second `httr2` timeout points to the source reader in this codebase; the new request URL and stage logs are intended to identify the actual failing connection on the next institution-side run.

The updated local suite passed 97 assertions with no failures, warnings, or skips. Both generated deployment copies and their manifest checksums were verified after regeneration. The institution-side timeout remains unverified until the updated diagnostics run there.

## Manifest repository validation

An institution-side log identified Connect 2025.02.0, R 4.4.3, and RHEL 8.10; failure occurred during Packrat repository resolution before the collector started. The associated local Windows transcript showed source-index access warnings during `rsconnect::writeManifest()`, despite successful binary installation through another CRAN host.

A local regression test reproduces rsconnect 1.11.2 writing null package repository URLs when its available-package index is empty. Manifest generation now checks named lockfile repositories, tests source-index access, validates package repository URLs, and stages both content items before replacing existing deployment files. Tests also verify that an unreadable index or invalid second manifest leaves both prior deployment directories intact.

The institution's actual generated manifest and successful redeployment remain to be verified. Current local validation uses R 4.5.3; it does not establish R 4.4.3 compatibility on that installation.

The expanded local suite passed 107 assertions with no failures, warnings, or skips. Both manifests were regenerated successfully against a reachable source index and their package repository URLs validated. No application extraction or snapshot schema changes were made for this build-time fix.

## Remaining target checks

The actual Connect installation has not been accessed. Private GitHub deployment, installed runtime compatibility, fresh package restoration, pins ownership/sharing, scheduling and overlap behavior, email recipients and delivery, and history preservation across redeployment remain required checks. Follow [the deployment guide](deployment.md) after transferring the code to the private repository.

The initial version uses Connect's email mechanism rather than a separate delivery ledger. Cross-host collector serialization is an operational prerequisite. Long-term retention and automatic cleanup of source archives/local working files remain operational decisions.
