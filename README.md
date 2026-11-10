# olsd-export

Planned automated export and change tracking for the [CHOP laboratory test menu](https://www.testmenu.com/chop).

The project will capture published test details, preserve historical snapshots, and make changes easy to review over time.

## Status

Planning stage. The repository currently contains the [project specification](SPEC.md); the collector, scheduled report, and web application have not been implemented. Installation and deployment instructions will be added alongside working code.

## Planned workflow

1. Collect all publicly discoverable test details daily, including send-out tests.
2. Export structured JSON for comparison and Excel for review.
3. Store accepted snapshots and run history using pins on institution-managed Posit Connect.
4. Compare accepted snapshots and report added, modified, missing, and removed tests with field-level before/after values.
5. Send email notifications and provide an R Shiny application for reviewing test and change history.

PDF link labels and destinations are included. PDF files and their contents are not collected. Incomplete collection runs must not replace the accepted baseline or produce false removal reports.

## Planned technology

- **R** with `httr2` and `rvest`/`xml2` for direct HTTP collection and HTML parsing.
- **JSON** as the authoritative export and basis for structured comparisons.
- **pins** for persistent snapshots and manifests.
- **R Markdown** for scheduled collection and reporting on Posit Connect.
- **Shiny** for browsing current details and historical changes.
- **renv** for reproducible R dependencies once implementation begins.

Browser automation is a fallback if site inspection shows that JavaScript execution is required. The source's discovery mechanism and page structure still need verification.

## Development plan

Start by verifying complete inventory discovery and extracting representative detail pages. Then validate pins access and scheduled execution on Connect before building complete snapshots, comparison logic, notifications, and the history application.

See [SPEC.md](SPEC.md) for scope, architecture, acceptance criteria, and outstanding deployment decisions.

Generated exports, captured source pages, local credentials, and runtime caches belong outside version control. Keep small, intentional test fixtures in a dedicated fixtures directory when tests are introduced.

## Copyright

Copyright © 2026 amromeo. See [COPYRIGHT](COPYRIGHT). An open-source license has not been selected.
