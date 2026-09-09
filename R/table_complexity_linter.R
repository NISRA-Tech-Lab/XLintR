#' Excel table complexity linter
#'
#' Functions for detecting table-like regions in Excel workbooks and
#' assessing their structural complexity.
#'
#' @keywords internal
#' @importFrom rlang .data
"_PACKAGE"

is_blank <- function(x) {
  is.na(x) | trimws(as.character(x)) == ""
}

safe_num <- function(x, default = 0) {
  if (length(x) == 0 || is.na(x)) default else as.numeric(x)
}

col_to_num <- function(col) {
  chars <- strsplit(toupper(col), "")[[1]]
  Reduce(
    function(acc, ch) acc * 26 + match(ch, LETTERS),
    chars,
    init = 0
  )
}

parse_a1_range <- function(x) {
  # Handles A1 or A1:C10
  parts <- strsplit(x, ":", fixed = TRUE)[[1]]

  parse_one <- function(cell) {
    m <- stringr::str_match(
      cell,
      "^\\$?([A-Za-z]+)\\$?([0-9]+)$"
    )

    if (any(is.na(m))) {
      return(c(row = NA_real_, col = NA_real_))
    }

    c(
      row = as.numeric(m[3]),
      col = col_to_num(m[2])
    )
  }

  a <- parse_one(parts[1])
  b <- if (length(parts) == 1) a else parse_one(parts[2])

  list(
    r1 = min(a["row"], b["row"], na.rm = TRUE),
    r2 = max(a["row"], b["row"], na.rm = TRUE),
    c1 = min(a["col"], b["col"], na.rm = TRUE),
    c2 = max(a["col"], b["col"], na.rm = TRUE)
  )
}

# -----------------------------
# Table detection
# -----------------------------

find_nonempty_components <- function(
    mat,
    min_cells = 4,
    bridge_gaps = 1
) {
  # Finds connected non-empty regions.
  #
  # bridge_gaps allows near-adjacent cells to belong to the same
  # table where blank separator cells exist.

  nr <- nrow(mat)
  nc <- ncol(mat)

  if (nr == 0 || nc == 0) {
    return(list())
  }

  nonempty <- !is_blank(mat)
  seen <- matrix(FALSE, nr, nc)
  components <- list()

  neigh <- function(r, c) {
    rr <- seq(
      max(1, r - bridge_gaps),
      min(nr, r + bridge_gaps)
    )

    cc <- seq(
      max(1, c - bridge_gaps),
      min(nc, c + bridge_gaps)
    )

    expand.grid(r = rr, c = cc)
  }

  k <- 0

  for (r in seq_len(nr)) {
    for (c in seq_len(nc)) {

      if (!nonempty[r, c] || seen[r, c]) {
        next
      }

      queue <- list(c(r, c))
      pts <- matrix(numeric(0), ncol = 2)

      seen[r, c] <- TRUE

      while (length(queue) > 0) {

        p <- queue[[1]]
        queue <- queue[-1]

        pts <- rbind(pts, p)

        nb <- neigh(p[1], p[2])

        for (i in seq_len(nrow(nb))) {

          rr <- nb$r[i]
          cc <- nb$c[i]

          if (nonempty[rr, cc] && !seen[rr, cc]) {

            seen[rr, cc] <- TRUE

            queue[[length(queue) + 1]] <- c(rr, cc)
          }
        }
      }

      if (nrow(pts) >= min_cells) {

        k <- k + 1

        components[[k]] <- list(
          r1 = min(pts[, 1]),
          r2 = max(pts[, 1]),
          c1 = min(pts[, 2]),
          c2 = max(pts[, 2]),
          nonempty_cells = nrow(pts)
        )
      }
    }
  }

  components
}

# -----------------------------
# Header heuristics
# -----------------------------

infer_header_depth <- function(
    x,
    max_scan = 8
) {
  # Header rows tend to contain more text than numbers
  # and often precede rows dominated by numeric values.

  if (nrow(x) == 0) {
    return(0L)
  }

  scan_n <- min(nrow(x), max_scan)

  row_stats <- purrr::map_dfr(
    seq_len(scan_n),
    function(r) {

      vals <- x[r, , drop = TRUE]
      vals <- vals[!is_blank(vals)]

      if (length(vals) == 0) {
        return(
          tibble::tibble(
            row = r,
            numeric_share = 0,
            text_share = 0
          )
        )
      }

      num_like <- suppressWarnings(
        !is.na(as.numeric(gsub(",", "", vals)))
      )

      tibble::tibble(
        row = r,
        numeric_share = mean(num_like),
        text_share = mean(!num_like)
      )
    }
  )

  # First row with majority numeric content is assumed
  # to be the start of the data body.

  first_data <- row_stats$row[
    row_stats$numeric_share >= 0.5
  ][1]

  if (is.na(first_data)) {
    return(min(1L, nrow(x)))
  }

  max(0L, first_data - 1L)
}

infer_row_header_depth <- function(
    x,
    max_scan = 5
) {

  if (ncol(x) == 0) {
    return(0L)
  }

  scan_n <- min(ncol(x), max_scan)

  col_stats <- purrr::map_dfr(
    seq_len(scan_n),
    function(c) {

      vals <- x[, c, drop = TRUE]
      vals <- vals[!is_blank(vals)]

      if (length(vals) == 0) {
        return(
          tibble::tibble(
            col = c,
            numeric_share = 0
          )
        )
      }

      num_like <- suppressWarnings(
        !is.na(as.numeric(gsub(",", "", vals)))
      )

      tibble::tibble(
        col = c,
        numeric_share = mean(num_like)
      )
    }
  )

  first_numeric_col <- col_stats$col[
    col_stats$numeric_share >= 0.5
  ][1]

  if (is.na(first_numeric_col)) {
    return(min(1L, ncol(x)))
  }

  max(0L, first_numeric_col - 1L)
}

# -----------------------------
# Workbook metadata extraction
# -----------------------------

get_merge_ranges <- function(
    wb,
    sheet
) {
  # openxlsx2 keeps merge definitions in worksheet XML
  # structures. This is deliberately defensive because
  # internal representations can differ by package version.

  ws <- wb$worksheets[[sheet]]

  candidates <- list(
    tryCatch(
      ws$mergeCells,
      error = function(e) NULL
    ),
    tryCatch(
      ws$merge_cells,
      error = function(e) NULL
    ),
    tryCatch(
      ws$mergeCells$mergeCell,
      error = function(e) NULL
    )
  )

  vals <- unlist(
    candidates,
    recursive = TRUE,
    use.names = FALSE
  )

  vals <- vals[
    grepl(
      "^[A-Za-z]+[0-9]+(:[A-Za-z]+[0-9]+)?$",
      vals
    )
  ]

  unique(vals)
}

count_hidden_rows_cols <- function(
    wb,
    sheet
) {
  ws <- wb$worksheets[[sheet]]

  xml_text <- paste(
    utils::capture.output(
      utils::str(ws, max.level = 3)
    ),
    collapse = "\n"
  )

  # Conservative fallback.
  #
  # Exact hidden-row/column extraction is dependent on
  # the openxlsx2 version.

  list(
    hidden_rows = stringr::str_count(
      xml_text,
      "hidden.?=.?1"
    ),
    hidden_cols = stringr::str_count(
      xml_text,
      "hidden.?=.?1"
    )
  )
}



# -----------------------------
# Actionable lint rules
# -----------------------------

make_issues <- function(
    score_obj
) {

  m <- score_obj$metrics

  issues <- list()

  add <- function(
    code,
    severity,
    issue,
    why,
    fix
  ) {

    issues[[length(issues) + 1]] <<-
      tibble::tibble(
        code = code,
        severity = severity,
        issue = issue,
        why = why,
        recommendation = fix
      )
  }

  # ---------------------------
  # T001
  # ---------------------------

  if (
    m$column_header_depth > 3
  ) {

    add(
      "T001",
      "high",
      "Deep column-header hierarchy",

      paste0(
        "The table appears to require ",
        m$column_header_depth,
        " column-header levels to interpret values."
      ),

      paste(
        "Reduce nested header levels.",
        "Consider moving one or more dimensions into",
        "ordinary columns or splitting the table into",
        "smaller tables."
      )
    )
  }

  # ---------------------------
  # T002
  # ---------------------------

  if (
    m$row_header_depth > 2
  ) {

    add(
      "T002",
      "medium",
      "Deep row-header hierarchy",

      paste0(
        "The table appears to use ",
        m$row_header_depth,
        " row-header levels."
      ),

      paste(
        "Flatten hierarchical row labels where possible,",
        "or repeat parent labels explicitly instead of",
        "relying on visual grouping."
      )
    )
  }

  # ---------------------------
  # T003
  # ---------------------------

  if (
    m$merge_count > 5 ||
    m$merged_cells >
    0.08 * (
      m$rows *
      m$columns
    )
  ) {

    add(
      "T003",
      "high",
      "Heavy use of merged cells",

      paste0(
        m$merge_count,
        " merged ranges affect approximately ",
        m$merged_cells,
        " cells."
      ),

      paste(
        "Use merges only for top-level visual grouping.",
        "Prefer repeated explicit labels or a normalized",
        "table with one variable per column."
      )
    )
  }

  # ---------------------------
  # T004
  # ---------------------------

  if (
    m$dimensionality >= 6
  ) {

    add(
      "T004",
      "high",
      "Many simultaneous dimensions",

      paste0(
        "A value may require roughly ",
        m$dimensionality,
        " attributes to describe it."
      ),

      paste(
        "Split the table by one high-level dimension,",
        "or convert the cross-tab to a tidy/long",
        "representation for analysis and provide a",
        "simpler presentation table for readers."
      )
    )
  }

  # ---------------------------
  # T005
  # ---------------------------

  if (
    m$header_blank_share > 0.25
  ) {

    add(
      "T005",
      "medium",
      "Blank cells inside header area",

      paste0(
        round(
          100 *
            m$header_blank_share
        ),
        "% of inferred header cells are blank."
      ),

      paste(
        "Repeat labels explicitly where blank cells imply",
        "'same as above' or 'same as left'.",
        "This reduces the amount of structure the reader",
        "has to infer."
      )
    )
  }

  # ---------------------------
  # T006
  # ---------------------------

  if (
    m$columns > 20
  ) {

    add(
      "T006",
      "medium",
      "Very wide table",

      paste0(
        "The detected table contains ",
        m$columns,
        " columns."
      ),

      paste(
        "Reduce horizontal scrolling by splitting the",
        "table, moving dimensions into rows, or providing",
        "filters or pivots for interactive use."
      )
    )
  }

  # ---------------------------
  # T007
  # ---------------------------

  if (
    m$hidden_rows +
    m$hidden_cols >
    0
  ) {

    add(
      "T007",
      "medium",
      "Hidden structure detected",

      paste0(
        "Detected hidden row/column indicators: ",
        m$hidden_rows +
          m$hidden_cols,
        "."
      ),

      paste(
        "Avoid making interpretation depend on hidden",
        "rows or columns. Put supporting definitions and",
        "calculations on clearly labelled sheets."
      )
    )
  }

  # ---------------------------
  # T008
  # ---------------------------

  if (
    m$cross_sheet_formula_share >
    0.1
  ) {

    add(
      "T008",
      "medium",
      "Cross-sheet formula dependence",

      paste(
        "A substantial share of visible cells appear",
        "to depend on other worksheets."
      ),

      paste(
        "For presentation sheets, separate calculation",
        "logic from displayed values and make",
        "source/provenance explicit."
      )
    )
  }

  # ---------------------------
  # No warnings
  # ---------------------------

  if (
    length(issues) == 0
  ) {

    add(
      "T000",
      "info",
      "No major structural complexity flags",

      paste(
        "The heuristic checks did not identify a",
        "strong structural barrier to interpretation."
      ),

      paste(
        "Still validate the table with representative",
        "users and real lookup questions; structural",
        "simplicity does not guarantee semantic clarity."
      )
    )
  }

  dplyr::bind_rows(issues)
}

# -----------------------------
# Sheet analysis
# -----------------------------

analyse_sheet <- function(
    wb,
    sheet_index,
    sheet_name,
    min_table_cells = 4
) {

  values <- openxlsx2::wb_to_df(
    wb,
    sheet = sheet_index,
    col_names = FALSE,
    skip_empty_rows = FALSE,
    skip_empty_cols = FALSE,
    fill_merged_cells = FALSE
  )

  formulas <- tryCatch(
    openxlsx2::wb_to_df(
      wb,
      sheet = sheet_index,
      col_names = FALSE,
      skip_empty_rows = FALSE,
      skip_empty_cols = FALSE,
      fill_merged_cells = FALSE,
      show_formula = TRUE
    ),
    error = function(e) NULL
  )

  mat <- as.matrix(values)

  components <- find_nonempty_components(
    mat,
    min_cells = min_table_cells,
    bridge_gaps = 1
  )

  merges <- get_merge_ranges(
    wb,
    sheet_index
  )

  hidden <- count_hidden_rows_cols(
    wb,
    sheet_index
  )

  if (
    length(components) == 0
  ) {

    return(
      list(
        summary = tibble::tibble(),
        issues = tibble::tibble(),
        details = list()
      )
    )
  }

  summaries <- list()
  all_issues <- list()
  details <- list()

  for (
    i in seq_along(components)
  ) {

    comp <- components[[i]]

    region <- mat[
      comp$r1:comp$r2,
      comp$c1:comp$c2,
      drop = FALSE
    ]

    region_formulas <- NULL

    if (
      !is.null(formulas)
    ) {

      fm <- as.matrix(
        formulas
      )

      if (
        nrow(fm) >= comp$r2 &&
        ncol(fm) >= comp$c2
      ) {

        region_formulas <- fm[
          comp$r1:comp$r2,
          comp$c1:comp$c2,
          drop = FALSE
        ]
      }
    }

    overlapping_merges <- purrr::keep(
      merges,
      function(rng) {

        p <- parse_a1_range(
          rng
        )

        !(
          p$r2 < comp$r1 ||
            p$r1 > comp$r2 ||
            p$c2 < comp$c1 ||
            p$c1 > comp$c2
        )
      }
    )

    sc <- score_table(
      region,
      merge_ranges =
        overlapping_merges,
      hidden_rows =
        hidden$hidden_rows,
      hidden_cols =
        hidden$hidden_cols,
      formula_matrix =
        region_formulas
    )

    table_id <- paste0(
      sheet_name,
      "_T",
      i
    )

    summaries[[i]] <- tibble::tibble(
      sheet = sheet_name,
      table_id = table_id,
      row_start = comp$r1,
      row_end = comp$r2,
      col_start = comp$c1,
      col_end = comp$c2,
      rows = nrow(region),
      columns = ncol(region),
      score = sc$score,
      complexity = sc$band,
      header_depth =
        sc$metrics$column_header_depth,
      row_header_depth =
        sc$metrics$row_header_depth,
      dimensions =
        sc$metrics$dimensionality,
      merged_ranges =
        sc$metrics$merge_count
    )

    iss <- make_issues(sc) |>
      dplyr::mutate(
        sheet = sheet_name,
        table_id = table_id,
        .before = 1
      )

    all_issues[[i]] <- iss

    details[[table_id]] <- sc
  }

  list(
    summary =
      dplyr::bind_rows(summaries),

    issues =
      dplyr::bind_rows(all_issues),

    details =
      details
  )
}



#' Print a table complexity report
#'
#' @param x A `table_complexity_report` object.
#' @param ... Additional arguments, currently unused.
#'
#' @return `x`, invisibly.
#'
#' @export
print.table_complexity_report <- function(
    x,
    ...
) {

  cat(
    "\nExcel Table Complexity Report\n"
  )

  cat(
    "=============================\n"
  )

  cat(
    "File:",
    x$file,
    "\n"
  )

  cat(
    "Workbook score:",
    x$workbook_score,
    "/ 100\n"
  )

  cat(
    "Complexity:",
    x$workbook_complexity,
    "\n\n"
  )

  if (
    nrow(x$summary) == 0
  ) {

    cat(
      "No table-like regions were detected.\n"
    )

    return(
      invisible(x)
    )
  }

  print(
    x$summary
  )

  cat(
    "\nTop recommendations:\n"
  )

  top <- x$issues |>
    dplyr::filter(
      .data$severity %in%
        c(
          "high",
          "medium"
        )
    ) |>
    utils::head(10)

  if (
    nrow(top) == 0
  ) {

    cat(
      "- No major structural issues flagged.\n"
    )

  } else {

    for (
      i in seq_len(
        nrow(top)
      )
    ) {

      cat(
        sprintf(
          "- [%s] %s (%s): %s\n",
          top$code[i],
          top$issue[i],
          top$table_id[i],
          top$recommendation[i]
        )
      )
    }
  }

  invisible(x)
}

# -----------------------------
# Command-line interface
# -----------------------------

args <- commandArgs(
  trailingOnly = TRUE
)

if (
  length(args) >= 1 &&
  file.exists(args[1])
) {

  report <- lint_workbook(
    args[1],
    write_csv = TRUE
  )

  print(report)
}
