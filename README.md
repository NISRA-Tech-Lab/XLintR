# XLintR

`XLintR` is an experimental R package for assessing how difficult Excel tables may be for a person to understand.

The package treats table readability as a structural problem. Rather than assessing the reading age of text, it looks at features such as nested headers, merged cells, table dimensions, hidden structure, formula dependencies, and the number of contextual labels a reader may need to interpret a value.

The aim is to provide something similar to a **linter for statistical tables**: identify potentially difficult structures, quantify their complexity, and give authors practical recommendations for improving them.

> **Status:** early-stage prototype.
> The complexity scores are heuristic and have not yet been validated against user comprehension testing.

## Why?

A spreadsheet can contain technically correct data while still being difficult to interpret.

For example, a value may only make sense after a reader has identified:

* the geography from a row header;
* the year from a merged column heading;
* the quarter from a second header level;
* the sex from a third header level;
* the measure or unit from a title or footnote.

The underlying data may be relatively straightforward, but the **presentation structure creates additional cognitive work**.

`XLintR` aims to make some of that complexity measurable.

## Installation

The package is currently under development.

If working from a local package project:

```r
devtools::load_all()
```

Once the package is hosted remotely, installation instructions can be added here.

## Basic usage

The main user-facing function is `lint_workbook()`.

```r
library(XLintR)

report <- lint_workbook("my_workbook.xlsx")

report
```

This scans the workbook, attempts to identify table-like regions, calculates complexity metrics, and generates lint-style recommendations.

You can inspect the results directly:

```r
report$summary
```

This contains one row per detected table.

```r
report$issues
```

This contains individual warnings and recommended improvements.

Detailed scoring information for each table is available in:

```r
report$details
```

## Example output

A workbook report may look something like:

```text
Excel Table Complexity Report
=============================

Workbook score: 67.4 / 100
Complexity: Difficult

Sheet       Table       Score  Complexity
Table 1     Table 1_T1   74.2  Difficult
Table 2     Table 2_T1   31.5  Easy
```

The corresponding issues might include:

```text
[T001] Deep column-header hierarchy

The table appears to require 5 column-header levels
to interpret values.

Recommendation:
Reduce nested header levels. Consider moving one or
more dimensions into ordinary columns or splitting
the table into smaller tables.
```

## Complexity measures

The current prototype considers several structural characteristics.

### Header depth

Tables with several nested levels of column or row headers require readers to retain more context while locating and interpreting a value.

For example:

```text
2026
└── Quarter 2
    └── Female
        └── Age 25–34
```

has a deeper interpretation path than:

```text
Year | Quarter | Sex | Age | Value
```

### Merged-cell burden

Merged cells are common in presentation tables and are not inherently problematic.

However, multiple levels of merged headings can create an implicit hierarchy that a reader must reconstruct before interpreting the data.

The package therefore considers both:

* the number of merged ranges;
* the number of cells affected by merging.

### Estimated dimensionality

A table may simultaneously encode several dimensions, for example:

```text
Geography × Year × Quarter × Sex × Age × Measure
```

The package estimates how many attributes may be required to uniquely describe an individual value.

This is used as an approximation of the reader's **lookup path**.

### Header ambiguity

Blank header cells may require the reader to infer that a previous heading still applies.

For example:

```text
Year     Sex      Value
2025     Male       10
         Female     12
```

may be visually understandable, but the second row depends on an implicit "`2025` same as above" relationship.

Explicit labels reduce this ambiguity.

### Table width

Very wide tables can make it difficult to maintain row and header context while scrolling horizontally.

The current scoring model applies additional complexity to particularly wide tables.

### Hidden structure

Hidden rows and columns can make workbook behaviour or interpretation less transparent.

Where detected, these are reported as potential complexity issues.

### Formula complexity

The prototype also examines formula use, including cross-sheet references.

This is primarily intended to identify cases where a presentation table depends heavily on calculations or structures elsewhere in the workbook.

## Complexity scores

Tables receive a score from `0` to `100`.

The current provisional bands are:

|  Score | Classification |
| -----: | -------------- |
|   0–20 | Very easy      |
|  21–40 | Easy           |
|  41–60 | Moderate       |
|  61–80 | Difficult      |
| 81–100 | Very difficult |

These boundaries are currently **heuristic**.

A score should therefore be interpreted as a diagnostic signal rather than an objective measure of human comprehension.

The long-term aim is to calibrate the model using real user testing.

## Lint rules

The package currently produces lint-style issues such as:

| Rule   | Issue                              |
| ------ | ---------------------------------- |
| `T001` | Deep column-header hierarchy       |
| `T002` | Deep row-header hierarchy          |
| `T003` | Heavy use of merged cells          |
| `T004` | Many simultaneous dimensions       |
| `T005` | Blank cells inside the header area |
| `T006` | Very wide table                    |
| `T007` | Hidden structure detected          |
| `T008` | Cross-sheet formula dependence     |

Each issue contains:

* a severity;
* an explanation;
* a recommendation for improving the table.

For example:

```r
report$issues
```

may return:

```text
code   severity   issue
T003   high       Heavy use of merged cells
T006   medium     Very wide table
```

alongside suggested fixes.

## Exporting results

Results can optionally be written to CSV files:

```r
report <- lint_workbook(
  "my_workbook.xlsx",
  write_csv = TRUE,
  output_dir = "output"
)
```

This creates:

```text
table_complexity_summary.csv
table_complexity_issues.csv
```

The summary contains table-level scores.

The issues file contains individual lint findings and recommendations.

## Scoring an individual table

Advanced users can score an already extracted table using `score_table()`.

```r
x <- data.frame(
  Region = c("A", "B", "C"),
  Male = c(10, 15, 20),
  Female = c(12, 18, 22)
)

score_table(x)
```

This returns the overall score, complexity band, underlying metrics, and individual score components.

## Design principles

The package is being developed around several principles.

### Explain the score

A complexity score by itself is not particularly useful.

Users should be able to see **why** a table received a particular score.

The package therefore exposes the individual metrics and scoring components rather than returning only a single number.

### Recommend changes

The purpose of linting is not simply to identify problems.

Each lint rule should provide a practical recommendation that helps the table author improve the structure.

### Distinguish data complexity from presentation complexity

Some datasets are inherently complex.

For example, a table describing:

```text
Geography × Age × Sex × Year × Measure
```

contains several dimensions regardless of how it is displayed.

A longer-term goal is therefore to distinguish:

```text
Intrinsic data complexity
```

from:

```text
Presentation complexity
```

This would help identify whether difficulty arises from the underlying information or from avoidable design choices.

### Do not treat every merged cell as an error

Merged cells can be useful for visually grouping related columns.

The aim is not to impose a blanket rule such as:

```text
merged cells = bad
```

Instead, the package should consider the hierarchy and cognitive burden created by those merges.

## Limitations

This package is currently experimental.

### Table detection

The current table-detection algorithm primarily identifies connected regions of populated cells.

This works for many conventional spreadsheets but may struggle with:

* titles immediately above tables;
* footnotes immediately below tables;
* multiple tables separated by only small gaps;
* heavily formatted publication spreadsheets;
* blank rows or columns used intentionally within tables.

Future versions may incorporate:

* cell styles;
* borders;
* merged-cell topology;
* Excel-defined tables;
* named ranges;
* value-type transitions;
* repeated structural patterns.

### Header detection

Header depth is currently inferred heuristically from the balance of text and numeric values near the beginning of a detected table.

Complex spreadsheets may therefore require more sophisticated structural inference.

### Complexity weights

The current scoring weights are provisional.

For example, the additional complexity assigned to header depth or merged cells reflects an initial design hypothesis rather than an empirically validated relationship with comprehension.

## Future work

Potential areas for development include:

* improved table-boundary detection;
* detection of titles, data regions and footnotes separately;
* detection of units and measures;
* identification of semantic information encoded only through colour or formatting;
* identification of repeated or ambiguous labels;
* separate intrinsic and presentation complexity scores;
* workbook-level HTML reports;
* visual highlighting of problematic table regions;
* accessibility checks;
* comparison of alternative table designs;
* configurable organisational lint rules;
* calibration against user comprehension testing.

A particularly important research direction is validation using real lookup tasks.

For example, participants could be asked:

> What was the female rate for Belfast in Quarter 2 of 2025?

Measures such as:

* whether the correct value was found;
* time taken;
* number of incorrect selections;
* confidence in the answer;

could then be compared with the structural metrics generated by the package.

This could eventually support an empirically grounded **table readability index**.

## Development

During package development:

```r
devtools::document()
devtools::load_all()
devtools::check()
```

Tests should be added for both the individual scoring components and representative workbook structures.

A useful test suite would include examples of:

* a simple rectangular table;
* a table with one grouped header;
* deeply nested headers;
* merged row and column headings;
* multiple tables on one worksheet;
* hidden rows or columns;
* cross-sheet formulas;
* intentionally difficult publication tables.

## Contributing

The package is at an early stage, so feedback on the scoring model is particularly valuable.

Useful contributions include:

* example spreadsheets that are easy or difficult to interpret;
* suggestions for additional structural metrics;
* evidence from table-design or accessibility research;
* alternative scoring approaches;
* test cases where table detection fails.

## Disclaimer

`XLintR` does not currently provide a validated measure of human comprehension, accessibility, or usability.

Its scores should be treated as **diagnostic heuristics** intended to help identify table structures that may deserve closer review.

Human review and user testing remain important, particularly for tables intended for public dissemination.
