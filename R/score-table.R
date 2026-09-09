#' Score the structural complexity of a table
#'
#' Calculates a heuristic complexity score for a rectangular table.
#'
#' The score is intended as a diagnostic measure rather than a validated
#' measure of human comprehension. The scoring weights should therefore
#' be interpreted as provisional.
#'
#' @param tbl A matrix or data frame containing the table.
#' @param merge_ranges Character vector of Excel merged-cell ranges,
#'   such as `"A1:C1"`.
#' @param hidden_rows Number of hidden rows associated with the table.
#' @param hidden_cols Number of hidden columns associated with the table.
#' @param formula_matrix Optional matrix containing formulas corresponding
#'   to `tbl`.
#'
#' @return A list containing the overall complexity score, complexity band,
#'   calculated metrics, and individual score components.
#'
#' @export
score_table <- function(
    tbl,
    merge_ranges = character(),
    hidden_rows = 0,
    hidden_cols = 0,
    formula_matrix = NULL
) {

  nr <- nrow(tbl)
  nc <- ncol(tbl)

  total <- max(1, nr * nc)

  nonempty <- sum(!is_blank(tbl))

  blank_share <- 1 - nonempty / total

  col_header_depth <- infer_header_depth(tbl)

  row_header_depth <- infer_row_header_depth(tbl)

  # ---------------------------
  # Merged cells
  # ---------------------------

  merge_parsed <- purrr::map(
    merge_ranges,
    parse_a1_range
  )

  merge_sizes <- purrr::map_dbl(
    merge_parsed,
    ~ (.x$r2 - .x$r1 + 1) *
      (.x$c2 - .x$c1 + 1)
  )

  merge_count <- length(merge_ranges)

  merged_cells <- sum(merge_sizes)

  max_merge_span <- ifelse(
    length(merge_sizes),
    max(merge_sizes),
    0
  )

  # ---------------------------
  # Approximate dimensionality
  # ---------------------------
  #
  # The basic idea is:
  #
  # row hierarchy
  # + column hierarchy
  # + the value/measure itself

  dimensionality <- max(
    1,
    row_header_depth +
      col_header_depth +
      1
  )

  lookup_path <- dimensionality

  # ---------------------------
  # Size pressure
  # ---------------------------

  width_pressure <- max(
    0,
    nc - 12
  ) / 12

  height_pressure <- max(
    0,
    nr - 40
  ) / 40

  # ---------------------------
  # Header ambiguity
  # ---------------------------

  header_blank_share <- 0

  if (col_header_depth > 0) {

    h <- tbl[
      seq_len(
        min(col_header_depth, nr)
      ),
      ,
      drop = FALSE
    ]

    header_blank_share <- mean(
      is_blank(h)
    )
  }

  # ---------------------------
  # Formula complexity
  # ---------------------------

  formula_share <- 0

  cross_sheet_formula_share <- 0

  if (
    !is.null(formula_matrix) &&
    length(formula_matrix)
  ) {

    fm <- as.matrix(
      formula_matrix
    )

    f <- grepl(
      "^=",
      fm
    )

    formula_share <- mean(
      f,
      na.rm = TRUE
    )

    cross_sheet_formula_share <- mean(
      f & grepl("!", fm),
      na.rm = TRUE
    )
  }

  # ---------------------------
  # Weighted complexity score
  # ---------------------------
  #
  # These weights are deliberately explicit.
  #
  # They are hypotheses, not validated readability
  # coefficients, and should eventually be calibrated
  # against actual comprehension testing.

  parts <- tibble::tibble(
    metric = c(
      "column_header_depth",
      "row_header_depth",
      "merge_burden",
      "dimensionality",
      "lookup_path",
      "header_ambiguity",
      "width",
      "height",
      "hidden_structure",
      "formula_complexity"
    ),

    raw = c(
      col_header_depth,
      row_header_depth,
      merged_cells / total,
      dimensionality,
      lookup_path,
      header_blank_share,
      width_pressure,
      height_pressure,
      hidden_rows + hidden_cols,
      formula_share +
        cross_sheet_formula_share
    ),

    points = c(

      # max 18
      min(
        18,
        col_header_depth * 5
      ),

      # max 12
      min(
        12,
        row_header_depth * 4
      ),

      # max 15
      min(
        15,
        (merged_cells / total) * 60 +
          merge_count * 0.8 +
          max_merge_span * 0.15
      ),

      # max 15
      min(
        15,
        max(
          0,
          dimensionality - 2
        ) * 4
      ),

      # max 10
      min(
        10,
        max(
          0,
          lookup_path - 3
        ) * 2.5
      ),

      # max 10
      min(
        10,
        header_blank_share * 20
      ),

      # max 7
      min(
        7,
        width_pressure * 3.5
      ),

      # max 3
      min(
        3,
        height_pressure
      ),

      # max 5
      min(
        5,
        (hidden_rows + hidden_cols) * 1.5
      ),

      # max 5
      min(
        5,
        formula_share * 6 +
          cross_sheet_formula_share * 10
      )
    )
  )

  score <- round(
    min(
      100,
      sum(parts$points)
    ),
    1
  )

  band <- cut(
    score,
    breaks = c(
      -Inf,
      20,
      40,
      60,
      80,
      Inf
    ),
    labels = c(
      "Very easy",
      "Easy",
      "Moderate",
      "Difficult",
      "Very difficult"
    )
  ) |>
    as.character()

  list(
    score = score,

    band = band,

    metrics = list(
      rows = nr,
      columns = nc,
      populated_cells = nonempty,
      blank_share = round(
        blank_share,
        3
      ),
      column_header_depth =
        col_header_depth,
      row_header_depth =
        row_header_depth,
      dimensionality =
        dimensionality,
      lookup_path =
        lookup_path,
      merge_count =
        merge_count,
      merged_cells =
        merged_cells,
      max_merge_span =
        max_merge_span,
      header_blank_share =
        round(
          header_blank_share,
          3
        ),
      hidden_rows =
        hidden_rows,
      hidden_cols =
        hidden_cols,
      formula_share =
        round(
          formula_share,
          3
        ),
      cross_sheet_formula_share =
        round(
          cross_sheet_formula_share,
          3
        )
    ),

    parts = parts
  )
}
