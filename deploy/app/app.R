library(shiny)
source("R/source.R", local = TRUE)
source("R/history.R", local = TRUE)

ui <- fluidPage(
  titlePanel("CHOP test menu history"),
  sidebarLayout(
    sidebarPanel(
      actionButton("refresh", "Refresh history"),
      textOutput("status"), hr(),
      selectInput("run", "Snapshot", choices = character()),
      selectizeInput("test", "Find a test", choices = character()),
      downloadButton("json", "Download JSON"),
      downloadButton("excel", "Download Excel")
    ),
    mainPanel(tabsetPanel(
      tabPanel("Test details", uiOutput("details")),
      tabPanel("Changes",
        checkboxInput("compare", "Compare two selected snapshots", FALSE),
        conditionalPanel("input.compare", selectInput("before", "Earlier snapshot", choices = character())),
        selectInput("type", "Change type", c("All", "added", "modified", "missing", "removed", "reappeared")),
        textInput("field", "Filter by field"),
        checkboxInput("selected_only", "Only the selected test", FALSE),
        dateRangeInput("dates", "Observed date range", start = Sys.Date() - 30, end = Sys.Date()),
        checkboxInput("all_runs", "Show changes across all runs", FALSE),
        selectInput("event", "Change to review", choices = character()),
        uiOutput("change")
      ),
      tabPanel("Run history", tableOutput("runs"))
    ))
  )
)

server <- function(input, output, session) {
  board <- history_board()
  history <- reactiveVal(NULL)
  observeEvent(input$refresh, {
    tryCatch(history(history_manifest(board)), error = function(e) showNotification(conditionMessage(e), type = "error"))
  }, ignoreNULL = FALSE)
  observe({
    manifest <- history()
    if (!length(manifest$runs)) return()
    runs <- manifest$runs
    choices <- setNames(vapply(runs, `[[`, "", "id"), vapply(runs, function(r) paste(display_time(r$collected_at), r$count, "tests"), ""))
    query <- parseQueryString(isolate(session$clientData$url_search))
    selected <- if (!is.null(query$run) && query$run %in% choices) query$run else tail(choices, 1)
    updateSelectInput(session, "run", choices = choices, selected = selected)
    updateSelectInput(session, "before", choices = choices, selected = if (length(choices) > 1) tail(choices, 2)[1] else choices[1])
  })
  selected_run <- reactive({
    req(history(), input$run)
    matches <- Filter(function(r) r$id == input$run, history()$runs)
    req(length(matches) == 1)
    matches[[1]]
  })
  snapshot <- reactive(history_snapshot(board, selected_run()))
  inventory <- reactive({
    tests <- snapshot()$tests
    # Include absent tests in the latest snapshot so their history remains accessible.
    if (identical(selected_run()$id, tail(history()$runs, 1)[[1]]$id)) {
      tests <- c(tests, lapply(history()$absent, `[[`, "test"))
    }
    tests
  })
  observe({
    tests <- inventory()
    ids <- vapply(tests, `[[`, "", "id")
    labels <- vapply(tests, function(t) paste(t$name, "—", t$number, "(", t$id, ")"), "")
    selected <- isolate(input$test)
    if (is.null(selected) || !selected %in% ids) selected <- ids[1]
    updateSelectizeInput(session, "test", choices = setNames(ids, labels), selected = selected, server = TRUE)
  })
  output$status <- renderText({
    input$refresh
    manifest <- history()
    status <- if (pins::pin_exists(board, history_name("last-attempt"))) pins::pin_read(board, history_name("last-attempt")) else NULL
    if (!length(manifest$runs)) {
      if (!is.null(status) && identical(status$status, "running")) {
        return(paste("Collection is running; started", display_time(status$started_at), ". See the collector render log for progress."))
      }
      if (!is.null(status) && identical(status$status, "failed")) {
        stage <- if (is.null(status$stage)) "unknown (older collector)" else status$stage
        return(paste("The last collection failed at stage", stage, ". See the collector render log for details."))
      }
      if (!inherits(board, "pins_board_connect")) {
        return(paste("No accepted snapshots found in", history_path("OLSD_BOARD_PATH", "outputs/board"),
          "for pin prefix", Sys.getenv("OLSD_PIN_PREFIX", "olsd"),
          ". If collection already succeeded, check that the collector used this folder and prefix."))
      }
      return("No accepted snapshots yet. Run the scheduled collector first.")
    }
    latest <- tail(manifest$runs, 1)[[1]]
    attempt_time <- if (!is.null(status$finished_at)) status$finished_at else status$started_at
    age <- difftime(Sys.time(), as.POSIXct(latest$collected_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours")
    paste("Last accepted:", display_time(latest$collected_at),
          if (!is.null(status)) paste("Last attempt:", status$status, display_time(attempt_time)) else "",
          if ((!is.null(status) && status$status == "failed") || age > 36) "Data may be stale." else "")
  })
  render_value <- function(value) {
    if (is.null(value)) return(tags$em("Absent"))
    if (is.character(value)) return(tags$p(value))
    if (!is.null(value$fields)) return(tagList(lapply(value$fields, render_value)))
    tagList(
      if (!is.null(value$label)) tags$h4(value$label),
      tags$p(value$text),
      lapply(value$tables, function(table) tags$table(class = "table table-bordered",
        lapply(table$rows, function(row) tags$tr(lapply(row, function(cell) {
          tag <- if (cell$header) tags$th else tags$td
          tag(cell$text, rowspan = cell$rowspan, colspan = cell$colspan)
        }))))),
      lapply(value$links, function(link) {
        # Source-provided links are untrusted input; permit ordinary web URLs only.
        if (grepl("^https?://", link$url, ignore.case = TRUE)) tags$p(tags$a(href = link$url, link$label, target = "_blank", rel = "noopener noreferrer"))
        else tags$p(link$label, " — ", link$url)
      }),
      lapply(value$images, function(image) tags$p("Image reference: ", image$alt, " ", image$url))
    )
  }
  render_fields <- function(fields) {
    groups <- unique(vapply(fields, `[[`, "", "section"))
    lapply(groups, function(group) tagList(tags$h3(gsub("([a-z])([A-Z])", "\\1 \\2", group)),
      lapply(Filter(function(f) f$section == group, fields), render_value)))
  }
  output$details <- renderUI({
    req(input$test)
    test <- Filter(function(t) t$id == input$test, inventory())
    req(length(test) == 1)
    test <- test[[1]]
    timeline <- unlist(lapply(history()$runs, function(r) {
      lapply(Filter(function(e) e$test_id == test$id, r$events), function(e) paste(display_time(r$collected_at), e$type, e$field))
    }), recursive = FALSE)
    present <- test$id %in% vapply(snapshot()$tests, `[[`, "", "id")
    tagList(tags$h3(test$name), tags$p("Code: ", test$number, " | ID: ", test$id),
      if (!isTRUE(snapshot()$complete)) tags$p("Sample snapshot: this is a partial export for review."),
      if (identical(snapshot()$source_mode, "archive")) tags$p("Reprocessed from retained source pages. Source capture window: ",
        display_time(snapshot()$source_window$first), " to ", display_time(snapshot()$source_window$last), "."),
      if (!present) tags$p("This test is absent from the selected snapshot. Details shown are from its last accepted appearance."),
      tags$a(href = test$source_url, "Source test page", target = "_blank", rel = "noopener noreferrer"),
      render_fields(test$fields),
      tags$h3("Observed changes"), if (length(timeline)) tags$ul(lapply(timeline, tags$li)) else tags$p("No changes recorded."))
  })
  events <- reactive({
    req(history())
    if (isTRUE(input$compare)) {
      req(input$before)
      earlier <- Filter(function(r) r$id == input$before, history()$runs)[[1]]
      validate(need(earlier$collected_at <= selected_run()$collected_at, "Choose an earlier snapshot as the starting point."))
      e <- catalog_diff(history_snapshot(board, earlier), snapshot())
      e <- lapply(e, function(x) { x$observed_at <- selected_run()$collected_at; x })
    } else {
      runs <- if (isTRUE(input$all_runs)) history()$runs else list(selected_run())
      e <- unlist(lapply(runs, function(r) lapply(r$events, function(x) {
        x$observed_at <- r$collected_at; x
      })), recursive = FALSE)
    }
    Filter(function(x) {
      (input$type == "All" || x$type == input$type) &&
        (!nzchar(input$field) || (!is.null(x$field) && grepl(tolower(input$field), tolower(x$field), fixed = TRUE))) &&
        (!isTRUE(input$selected_only) || is.null(input$test) || !nzchar(input$test) || x$test_id == input$test) &&
        (is.null(input$dates) || {
          day <- as.Date(as.POSIXct(x$observed_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                         tz = Sys.getenv("OLSD_DISPLAY_TZ", "America/New_York"))
          day >= input$dates[1] && day <= input$dates[2]
        })
    }, e)
  })
  observe({
    e <- events()
    labels <- vapply(e, function(x) paste(display_time(x$observed_at), x$type, x$name, x$field), "")
    updateSelectInput(session, "event", choices = setNames(as.character(seq_along(e)), labels))
  })
  output$change <- renderUI({
    e <- events()
    if (!length(e)) return(tags$p("No changes match the selected filters."))
    req(input$event)
    i <- as.integer(input$event); req(i >= 1, i <= length(e))
    value <- e[[i]]
    tagList(tags$h3(value$name), tags$p(value$type, " — ", value$field),
      fluidRow(column(6, tags$h4("Before"), render_value(value$before)),
               column(6, tags$h4("After"), render_value(value$after))))
  })
  output$runs <- renderTable({
    req(history())
    do.call(rbind, lapply(history()$runs, function(r) data.frame(
      run = r$id, collected = display_time(r$collected_at), tests = r$count,
      baseline = r$baseline, events = r$event_count)))
  })
  download <- function(ext) downloadHandler(
    filename = function() paste0("chop-", selected_run()$id, ".", ext),
    content = function(file) {
      paths <- pins::pin_download(board, selected_run()$pin)
      file.copy(paths[basename(paths) == paste0("snapshot.", ext)], file, overwrite = TRUE)
    })
  output$json <- download("json")
  output$excel <- download("xlsx")
}

shinyApp(ui, server)
