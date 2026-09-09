#' Assess the complexity of tables in an Excel workbook
#'
#' Detects table-like regions in an Excel workbook and assesses their
#' structural complexity using measures including header depth, merged-cell
#' burden, estimated dimensionality, lookup path length, table width,
#' hidden structure, and formula complexity.
#'
#' @param path Path to an `.xlsx` workbook.
#' @param min_table_cells Minimum number of populated cells required for a
#'   region to be considered a possible table.
#' @param write_csv Logical. If `TRUE`, write table-level results and lint
#'   issues to CSV files.
#' @param output_dir Directory in which CSV output should be written.
#'   Defaults to the directory containing `path`.
#'
#' @return An object of class `table_complexity_report`. The object contains:
#' \describe{
#'   \item{file}{The analysed workbook path.}
#'   \item{workbook_score}{Overall workbook complexity score from 0 to 100.}
#'   \item{workbook_complexity}{Complexity classification.}
#'   \item{summary}{Table-level complexity results.}
#'   \item{issues}{Lint issues and recommendations.}
#'   \item{details}{Detailed scoring components for each detected table.}
#' }
#'
#' @examples
#' \dontrun{
#' report <- lint_workbook("tables.xlsx")
#' report
#' report$summary
#' report$issues
#' }
#'
#' @export
lint_workbook <- function(
    path,
    min_table_cells = 4,
    write_csv = FALSE,
    output_dir = NULL
) {

  stopifnot(
    file.exists(path)
  )

  wb <- openxlsx2::wb_load(path)

  sheets <- wb$get_sheet_names()

  results <- purrr::map2(
    seq_along(sheets),
    sheets,
    ~ analyse_sheet(
      wb,
      .x,
      .y,
      min_table_cells =
        min_table_cells
    )
  )

  summary <- dplyr::bind_rows(
    purrr::map(
      results,
      "summary"
    )
  ) |>
    dplyr::arrange(
      dplyr::desc(.data$score)
    )

  issues <- dplyr::bind_rows(
    purrr::map(
      results,
      "issues"
    )
  ) |>
    dplyr::mutate(
      severity = factor(
        .data$severity,
        levels = c(
          "high",
          "medium",
          "low",
          "info"
        )
      )
    ) |>
    dplyr::arrange(
      .data$severity,
      dplyr::desc(.data$table_id)
    )

  details <- purrr::flatten(
    purrr::map(
      results,
      "details"
    )
  )

  if (
    nrow(summary)
  ) {

    workbook_score <- round(
      stats::weighted.mean(
        summary$score,
        pmax(
          1,
          summary$rows *
            summary$columns
        )
      ),
      1
    )

  } else {

    workbook_score <- 0
  }

  workbook_band <- cut(
    workbook_score,
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

  out <- list(
    file =
      normalizePath(path),

    workbook_score =
      workbook_score,

    workbook_complexity =
      workbook_band,

    summary =
      summary,

    issues =
      issues,

    details =
      details
  )

  class(out) <- c(
    "table_complexity_report",
    class(out)
  )

  # Optional CSV output

  if (
    write_csv
  ) {

    if (
      is.null(output_dir)
    ) {
      output_dir <- dirname(path)
    }

    dir.create(
      output_dir,
      recursive = TRUE,
      showWarnings = FALSE
    )

    utils::write.csv(
      summary,
      file.path(
        output_dir,
        "table_complexity_summary.csv"
      ),
      row.names = FALSE
    )

    utils::write.csv(
      issues,
      file.path(
        output_dir,
        "table_complexity_issues.csv"
      ),
      row.names = FALSE
    )
  }

  out
}
