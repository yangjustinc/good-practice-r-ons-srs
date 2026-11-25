# Good Practice for R Users When Working in the ONS SRS

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24343725.svg)](https://doi.org/10.5281/zenodo.24343725)

Materials for a one-hour workshop on writing efficient, reproducible and robust R code for large linked administrative data in the [ONS Secure Research Service](https://www.ons.gov.uk/aboutus/whatwedo/statistics/requestingstatistics/secureresearchservice) (SRS) and similar trusted research environments. First delivered through [Datacise Open Learning](https://dataciseopenlearning.org/courses/good-practice-for-r-users-when-working-in-the-ons-srs/) on 25 November 2026 (live on Microsoft Teams). A recording will be linked here once Datacise shares it.

## Start here

Read online at **<https://yangjustinc.github.io/good-practice-r-ons-srs/>**, or here on GitHub:

**[LESSON.md](LESSON.md)** sets out the learning objectives, then follows the session section by section: the code, the outputs to expect, the questions asked, and material there wasn't time for live. It ends with a self-check (answers hidden) and a quick-reference sheet. You can read it without running anything.

## What it covers

- the unit data arrive in vs. the unit the analysis needs;
- reducing rows, columns and granularity early, and letting the database do the work (DBI + dbplyr);
- memory, saved intermediates and avoiding recomputation;
- join cardinality, key checks, and a wrong join that runs without error;
- missing records vs. true zeroes, and validation checks;
- comments, functions and a rerunnable pipeline.

SRS data can't leave the SRS, so the examples use public data with the same structural problems: NYC Taxi & Limousine Commission **High Volume For-Hire Vehicle trip records, 2024** (~20 million trips a month, ~240 million in the year).

## The code

| Script | What it does |
|---|---|
| [`00_download_and_prepare.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/00_download_and_prepare.R) | Downloads the data; writes a seven-column January CSV and a small fallback sample |
| [`01_workflow_data_table.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/01_workflow_data_table.R) | The complete worked example, with executable checks |
| [`02_workflow_dplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/02_workflow_dplyr.R) | The same workflow in dplyr |
| [`03_full_year_arrow.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/03_full_year_arrow.R) | The whole year with Arrow, without loading it into R |
| [`04_database_dbplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/04_database_dbplyr.R) | Letting a database do the work with DBI + dbplyr (DuckDB here; SQL Server in the SRS) |

To run the code, open `teaching.Rproj` and follow [Setting up in LESSON.md](LESSON.md#setting-up). No data are included in this repository; [`data/MANIFEST.csv`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/data/MANIFEST.csv) records checksums of the files the materials were developed with.

## Data source

NYC Taxi & Limousine Commission, [TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page): High Volume For-Hire Vehicle Trip Records (2024) and the Taxi Zone Lookup Table, published by the City of New York as open data. These materials are not affiliated with or endorsed by the TLC or ONS.

## Citation and licence

Please cite these materials if you use or adapt them:

> Yang, J. (2026). *Good Practice for R Users When Working in the ONS SRS: workshop materials*. Zenodo. <https://doi.org/10.5281/zenodo.24343725>

For other formats, see [CITATION.cff](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/CITATION.cff), or "Cite this repository" on GitHub. Lesson text is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); code is [MIT](https://opensource.org/license/mit). See [LICENSE.md](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/LICENSE.md).

The advice draws on population-level linked education and health research in the ONS SRS. The views expressed are the author's own.
