# CHOP Test Menu Export and Change Detection

Status: Approved high-level specification. User-confirmed scope, platform choices, and deployment path are incorporated; remaining operational defaults are identified below. No implementation has begun.

## Goal

Automatically export the actual test details published in the CHOP laboratory test menu at `https://www.testmenu.com/chop`, retain historical snapshots, and produce an understandable account of what changed. First deployment target: Posit Connect.

The first release includes a scheduled collection and reporting job, email notifications, and a web application for reviewing changes over time. Deployment target: institution-managed Posit Connect, using R and pins for persistence.

## Proposed scope

- Collect every test discoverable through the public CHOP menu, including send-outs.
- Capture all information on each test detail page. Preserve unfamiliar sections rather than silently dropping them.
- Extract detail-page links, including PDF links, with their labels and destinations. Changes to these links are in scope; downloading PDFs or comparing their contents is out of scope.
- No login is required to read the source menu.
- Exclude navigation, site-wide notices outside test details, styling, and unrelated website content.
- Do not interpret catalog changes as clinical recommendations.

Coverage means the tests the site's public discovery mechanisms expose. Confirm whether search, alphabetical lists, categories, or another index provide the authoritative inventory before promising a complete export.

## Proposed first-release outputs

1. A complete JSON snapshot, preserving structured fields and repeatable sections.
2. An Excel workbook with a test index, one row per test, and additional sheets where repeating information would otherwise be lost.
3. An HTML change report with added, provisionally missing, confirmed removed, and modified tests; modified tests show field-level before/after values and source links.
4. Run metadata and retained source responses or rendered detail HTML sufficient to investigate extraction problems.
5. An R Shiny application for searching tests, browsing their history, and reviewing changes across accepted snapshots.
6. Email notifications summarizing detected changes and linking to the application.

JSON is the authoritative export and the basis for structured comparisons; Excel is the convenient review format. Run daily. Proposed default: send a change email only when an accepted run detects changes, with failure notifications to an operator and a baseline-established email on the first successful run. Recipients and execution time remain to be configured.

## Architecture

Two Connect content items share a pins board:

- A scheduled R Markdown report performs discovery, collection, normalization, validation, comparison, persistence, and email reporting.
- A read-only R Shiny application reads published snapshots and change records. Opening or refreshing the application does not initiate a crawl.

Use R with `httr2` for HTTP requests, `rvest`/`xml2` for HTML extraction, `jsonlite` for JSON, `pins` for persistence, and an Excel-writing package such as `writexl`. Lock the eventual package environment with `renv` during implementation.

Start with direct HTTP requests. A short discovery spike must establish whether inventory and details are present in returned HTML or accessible through the site's underlying data endpoints. Playwright is a fallback only if executing JavaScript is necessary; it is not a first-release prerequisite unless that spike demonstrates a need.

Conceptual flow:

`discover inventory -> collect details -> normalize -> validate completeness -> compare -> publish accepted snapshot and report`

Failed or incomplete runs publish a run-status report but do not advance the accepted baseline.

## Pins persistence

Use a shared Connect-backed pins board (`pins::board_connect()`), subject to verification on the installed Connect version. Pins is the persistence interface, not a relational database; the application will read explicit manifests and snapshot artifacts rather than issue database queries.

- Write an immutable bundle for each run containing its metadata, JSON snapshot, Excel export, change records, and retained source artifacts as appropriate.
- Maintain a compact published manifest listing accepted runs, their artifact locations, and the latest accepted baseline. Keep failed-run status separately available for operational review.
- Write and verify a complete bundle before publishing its manifest entry. Serialize collector executions so only one writer updates the manifest. An interrupted write may leave an unreferenced bundle; it must not expose an incomplete snapshot to readers.
- Read the manifest once per application refresh, then load the referenced immutable artifacts so a page does not mix runs.
- Configure writer access for the scheduled content and reader access for the application identity and intended viewers. Verify supported noninteractive Connect authentication and sharing; do not assume source-public content implies public application access.
- Define and test retention explicitly. Do not rely on default pin version retention as the sole historical archive. Proposed initial policy: retain all accepted JSON snapshots and change records; decide raw-page retention after measuring storage volume.

## Collection behavior

- Enumerate all supported inventory pages and pagination; deduplicate links before collecting details.
- Use a source-provided stable test identifier when available. Keep names, order codes, URLs, and aliases separately. Do not use the test name alone as identity.
- Treat a URL or name change as a modification when stable identity confirms continuity. Flag ambiguous matches for review rather than silently merging them.
- Preserve section labels, meaningful ordering, tables, units, symbols, reference ranges, and repeated entries.
- Resolve relative PDF/document links against their source page. Preserve meaningful URL parameters; compare both link labels and destinations. A PDF whose contents change at the same URL will not be detected by this release.
- Example fields to verify during inspection: test name, codes, synonyms, specimen requirements, collection and transport instructions, stability, methodology, turnaround time, performing laboratory, reference values, interpretation, limitations, and ordering information. These are candidate fields, not a verified description of the source.
- Use conservative concurrency, timeouts, bounded retries, and explicit handling of pagination failures, redirects, access errors, and unexpected page templates.

## Snapshot and comparison model

Each run records its ID, start/end times, source, collector/schema versions, inventory count, collected count, failures, and acceptance status. Each test records source identity, source URL, structured details, and collection time. Collection time is not a source modification time.

Retain original extracted content alongside normalized values. Normalize whitespace and markup for comparison, while preserving clinically meaningful punctuation, numbers, units, case, and table relationships. Configure ordering rules by field; do not sort all content indiscriminately.

Compare each accepted run with the previous accepted run. The first accepted run establishes a baseline and reports its inventory without calling every test newly added. A no-change run still produces a successful status record.

Report additions, removals, and field changes, including previously unknown sections. Show old and new values, test identity, and source links. Hashes may accelerate comparison but do not replace readable differences.

Proposed removal rule: a test absent from a complete run becomes provisionally missing; confirm removal only after a second complete run also lacks it. A failed detail request is a collection failure, not evidence of removal. Show reappearances explicitly.

Extractor or schema changes must be distinguishable from source changes. Reprocess retained source artifacts where possible or mark the comparison as requiring review rather than presenting parser changes as catalog edits.

## Completeness and reliability

Accept a snapshot only when inventory traversal completes and every discovered test is collected or accounted for by an explicit, reviewed exception. Unexpected empty inventories, major inventory drops, missing expected sections, and identity collisions block automatic acceptance pending investigation. Set thresholds after observing actual inventory size and normal variation.

Store run outputs under unique IDs and update the accepted-snapshot pointer only after validation and durable writes succeed. Prevent overlapping scheduled jobs from racing to update the baseline. Rerunning the same content must not create false change events.

## Change-review application and email

The Shiny application provides:

- Latest successful collection time, last attempt status, inventory size, and a visible stale-data indicator when collection is failing.
- A searchable test inventory, current detail view, and per-test timeline, including removed tests.
- A change feed filterable by date/run, test, change type, and changed field.
- Side-by-side old/new field values, preserving table context, with source links. A historical change describes when it was observed; it does not establish when the source was edited.
- Selection of two accepted snapshots for comparison, plus JSON and Excel downloads for a selected snapshot.
- Stable links from emails to a specific run's changes.

Proposed email content: run time, counts of added/modified/missing/removed tests, a short summary, and a link to the relevant view. Notify only after artifacts and the manifest are published. Key delivery records by run ID to reduce duplicate notifications on retries; document the retry behavior of the chosen email mechanism.

Prefer Connect's scheduled-report email capability if the institution's installation supports the required recipients and conditional-send behavior. Validate this before selecting the exact delivery mechanism. If an alternative institution-supported mail service is needed, make that an explicit deployment dependency. Failure alerts must identify that the previous accepted snapshot remains in use.

## Posit Connect deployment

Verify in the actual Connect execution environment:

- Supported R runtime, package installation/restoration, scheduled R Markdown execution, and Shiny hosting.
- Outbound access to the menu and any required resource hosts.
- Connect-backed pins reads/writes from the scheduled content and reads from the Shiny content, including permissions and persistence across redeployment.
- Scheduled-report email configuration, recipient access, and conditional-send/failure notification behavior.
- Execution time limits, scheduling timezone, and overlap controls.
- Only if direct extraction fails: whether browser automation is supported and necessary.

Deploy the scheduled R report and Shiny application separately, sharing collector/comparison functions within the repository. Reproduce dependencies with `renv` and the institution's supported Connect deployment workflow. Proposed scheduling timezone: America/New_York; store timestamps in UTC and display timezone labels in the report and application.

### GitHub-backed deployment path

1. Develop and publish reusable source, documentation, dependency lockfiles, and required deployment manifests in the public `amromeo/olsd-export` repository.
2. The user pulls the public changes and pushes the selected revision to an institution-controlled private GitHub repository. This transfer is user-managed; automatic mirroring is outside the initial scope.
3. Posit Connect uses GitHub-backed deployment from the private repository, with separate content configurations for the scheduled report and Shiny application.

Keep the application portable between repository locations: no dependency on the public remote at runtime, a particular checkout directory, or developer-local files. During implementation, provide the entry points and manifests required by the installed Connect version, and verify that Git-backed deployment includes shared R code and restores dependencies for both content items.

Configure institution-specific Connect URLs, pins locations, recipients, and runtime credentials through supported deployment settings or private configuration. Public examples use placeholders. Runtime snapshots, captured pages, and exports remain in pins or local ignored output paths rather than being committed to either source repository.

Record the deployed source revision in run metadata where the deployment exposes it, and document how the user can identify the corresponding public revision. Code redeployment must preserve pins history and the accepted baseline. Verify the private-repository deployment trigger, scheduled execution, and application refresh behavior on the actual Connect installation.

The source requires no login. Connect publishing, pins access, and email may require deployment credentials or service identities, configured through institution-supported mechanisms rather than embedded in code.

## Validation and acceptance

1. Reconcile discovery against the source's full inventory mechanism; manually inspect representative tests with complex tables, send-out details, and long instructions.
2. Export every discovered test in a successful run without losing detail sections or table structure.
3. Repeat an unchanged run and verify there are no content changes.
4. Exercise controlled fixtures for additions, removals, renamed tests, numerical/unit edits, table changes, and formatting-only changes; verify readable and correct results.
5. Simulate a failed page, broken pagination, and truncated inventory; verify that none replaces the accepted baseline or generates false removals.
6. Run the deployed job on Connect twice, including a fresh process, and verify that history persists and comparison uses the previous accepted snapshot.
7. Confirm PDF links appear in exports and link changes appear in diffs, without downloading PDF contents.
8. Verify the Shiny history, filters, comparison views, removed-test lookup, and downloads against known snapshots; verify emails link to the correct run.
9. Simulate an interrupted pins write and a retried run; verify readers see only complete published snapshots and notification retries follow the documented behavior.
10. Deploy both content items through Connect's private-GitHub-backed workflow after the user transfers a public revision; verify shared-code inclusion, dependency restoration, runtime configuration, and preservation of pins history across redeployment.

## Implementation sequence

1. Inspect the source and Connect capabilities; demonstrate complete discovery and a few representative extractions.
2. Review sample JSON/Excel exports and field differences; agree on schema, normalization, and identity rules.
3. Implement complete snapshots, durable storage, and completeness gates.
4. Implement readable differences, the Shiny history application, and scheduled Connect reports with email notifications.
5. Validate repeated deployment runs and document operations, retention, and recovery.

## Open decisions

- Exact daily execution time and confirmation of the proposed America/New_York display/scheduling timezone.
- Email recipients, operator for failures, and confirmation of change-only notification defaults.
- Connect version, publishing permissions, shared pins board configuration, application audience, and available email capabilities.
- Raw-source retention period and acceptable storage volume; long-term accepted snapshot retention policy.

These deployment details do not block drafting the collector and comparison design. Site inspection and a Connect feasibility check are needed before finalizing implementation choices.

## Current evidence and limits

The repository was empty at planning start. No source code has been implemented. Direct inspection of `testmenu.com` was blocked by this cloud environment's outbound policy; the menu's page structure, inventory mechanism, identifiers, and endpoints remain unverified. Posit Connect runtime capabilities have not yet been tested. These checks are the first implementation milestone.
