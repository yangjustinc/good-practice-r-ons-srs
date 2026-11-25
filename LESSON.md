# Lesson notes

These notes follow the live session section by section, so you can revisit it or work through it on your own. They also include material there wasn't time for live.

**You don't need to run anything to follow these notes.** Every step shows the output to expect. If you want to run the code, see [Setting up](#setting-up) at the end.

## What you'll be able to do

By the end of the session (or of these notes) you should be able to:

1. work out what one row is, and what your question actually needs (§1–2);
2. cut data down early, ideally in the database, and spot code that doesn't (§3);
3. decide what to save once and what to rerun (§4);
4. check that a join did what you expected (§2, §5);
5. tell a missing record from a real zero (§6);
6. write your assumptions into your code (§7–8).

In the session, each of these is practised on an SRS-style example. Those questions are included below, marked **❓ SRS question**. The [self-check](#check-your-understanding) at the end is optional extra practice.

**Contents**

1. [Why workflows need different design in the SRS](#1-why-workflows-need-different-design-in-the-srs)
2. [Units, identifiers and join relationships](#2-units-identifiers-and-join-relationships)
3. [Working with less data](#3-working-with-less-data)
4. [Managing computational cost](#4-managing-computational-cost)
5. [Combining linked data safely](#5-combining-linked-data-safely)
6. [Missingness, structural zeroes and validation](#6-missingness-structural-zeroes-and-validation)
7. [Reproducible workflows](#7-reproducible-workflows)
8. [Reflect on your own workflow](#8-reflect-on-your-own-workflow)
9. [Check your understanding](#check-your-understanding)
10. [Quick reference](#quick-reference)
11. [Setting up](#setting-up)

**The worked example.** NYC High Volume For-Hire Vehicle trips (Uber, Lyft and similar), 2024.

> **Research question:** how does trip activity vary across NYC pickup zones and over time?
> **Source unit:** one row = one trip. **Analytical unit:** one row = pickup zone × day.

The full code is in [`code/01_workflow_data_table.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/01_workflow_data_table.R) (the same analysis in dplyr: [`code/02_workflow_dplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/02_workflow_dplyr.R)). Each section below names the matching step.

> **Pause and predict.** Questions marked ❓ were asked in the session. Try to answer each one before reading on: committing to a prediction is what makes the result stick.

---

## 1. Why workflows need different design in the SRS

In the SRS you typically work on a shared virtual machine with a fixed memory ceiling, read from network storage, use a fixed set of package versions without internet access, and have every output checked for disclosure. Memory you waste and computation you repeat slow you down, and can slow down other researchers on the same machine.

❓ *What do you expect one row of the trip file to represent?*

```r
trips <- fread("data/teaching_csv/fhvhv_tripdata_2024-01_selected.csv")
dim(trips)                                  # 19,663,930 rows x 7 columns
format(object.size(trips), units = "GB")    # ~0.8 GB
```

One row is one trip. That is one month; the year has ~240 million.

❓ *Does the research question need one row per trip?* No: it needs one row per zone per day.

**In the SRS:** admissions, attendances, exclusions and benefit spells arrive as events, while analyses usually need person-years, school-years or area-months.

❓ **SRS question.** *You've got A&E data with one row per visit. Your question: how many children went to A&E at least once each year? What should one row be?*

One row per child per year, with a yes/no for whether they went. If you kept one row per visit and counted rows, a child with five visits would be counted five times.

> **Key point:** the shape the data come in isn't necessarily the shape you want to analyse.

## 2. Units, identifiers and join relationships

*Script step 4.* The zone lookup has 265 rows, one per taxi zone.

❓ *Which column should be unique? Will these checks return any rows?*

```r
zones[, .N, by = LocationID][N > 1]   # 0 rows: LocationID is a key
zones[, .N, by = Zone][N > 1]         # 2 rows: zone NAMES repeat
```

"Corona" is two zones (IDs 56 and 57), and "Governor's Island/Ellis Island/Liberty Island" is three (103–105). A name that looks like an identifier is not one. In administrative data the same is true of school names, GP practice names, local-authority names and postcodes. Join on the identifier (URN, pseudonymised person ID).

❓ *Does `PULocationID` uniquely identify a trip?* No. Many trips share a zone.

Every join has an expected **cardinality**: one-to-one, one-to-many, many-to-one or many-to-many. Trips → zones is **many-to-one**. Decide which you expect *before* joining, because it tells you what to check afterwards.

> **Key point:** just because a column looks like an ID doesn't mean it's a key.

## 3. Working with less data

*Script steps 1 and 3; [`code/04_database_dbplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/04_database_dbplyr.R).*

The only `data.table` grammar used in this lesson is

```
DT[ i,            j,                  by ]
    which rows?   what to compute?    within which groups?
```

plus `:=`, which adds a column **by reference**, without copying the table:

```r
trips[, pickup_date := as.IDate(pickup_datetime)]
```

The refrain for the whole session: **reduce rows, reduce columns, reduce granularity, as early as is analytically legitimate.**

### Let the database do the work

In the SRS your source data are usually in **SQL Server tables**. The most important efficiency decision is *where* the filtering and aggregation run. With DBI + dbplyr you write dplyr code, dbplyr translates it into SQL, the database runs it, and only the result comes back to R.

The session used DuckDB, a database that runs inside R, to stand in for SQL Server. Only the connection line differs:

```r
library(DBI); library(dplyr)

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "CREATE VIEW hvfhv AS SELECT * FROM read_parquet('data/raw_parquet/*.parquet')")
trips_db <- tbl(con, "hvfhv")
trips_db                      # "?? x 24": all of 2024 (~240M rows), nothing read yet

daily_zone_db <- trips_db |>
  filter(pickup_datetime < "2024-02-01") |>
  mutate(pickup_date = as.Date(pickup_datetime)) |>
  count(PULocationID, pickup_date)

show_query(daily_zone_db)     # the SQL the database will run
collect(daily_zone_db)        # 8,006 rows, in under a second
```

❓ *Where does the computation happen?* In the database. Nothing runs until `collect()`.

**Avoid** `tbl(con, ...) |> collect() |> filter(...)`. It copies the entire table into R before reducing it, and it is the most common, most expensive mistake when querying SRS databases from R.

**In the SRS**, the connection looks something like this. Ask SRS support for the exact driver, server and database names.

```r
con <- dbConnect(odbc::odbc(), Driver = "SQL Server", Server = "<server>",
                 Database = "<database>", Trusted_Connection = "Yes")
events <- tbl(con, I("dbo.<table>"))
```

To see the T-SQL your code will send to SQL Server without connecting to one, run section 2 of [`code/04_database_dbplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/04_database_dbplyr.R) (`simulate_mssql()`).

❓ **SRS question.** *Which one drags the whole table into R first?*

```r
# A
tbl(con, "episodes") |> collect() |> filter(year >= 2015) |> count(person_id)
# B
tbl(con, "episodes") |> filter(year >= 2015) |> count(person_id) |> collect()
```

**A.** `collect()` comes before `filter()`, so every row comes into R and is filtered there. In B the database does the filtering and counting, and only one row per person comes back. If you see `collect()` early in a pipeline, treat it as a warning sign.

> **Key point:** only move the data you need, and do the cutting down where the data live.

## 4. Managing computational cost

*Script step 3.*

❓ *Will aggregating to zone-day produce more rows, fewer, or the same?*

```r
daily_zone <- trips[, .(n_trips = .N, mean_base_fare = mean(base_passenger_fare)),
                    by = .(PULocationID, pickup_date = as.IDate(pickup_datetime))]
```

19,663,930 rows (~0.9 GB) become 8,006 rows (~0.2 MB). Save that intermediate, and the event-level table no longer needs to exist:

```r
saveRDS(daily_zone, "derived/zone_day_2024_01.rds")
rm(trips)
```

- **Expensive and stable steps** (extraction, cleaning, aggregation): compute once and save.
- **Cheap and changing steps** (models, tables, plots): rerun freely.

Calling `gc()` is not the optimisation; designing the workflow so that the huge object stops being needed is.

❓ **SRS question.** *Save it once, or rerun it? (a) pulling ten years of hospital episodes; (b) fitting your regression; (c) formatting your output table.*

(a) Save: slow and stable. (b) and (c) Rerun: quick, and you'll keep changing them.

### What the benchmarks showed

Measured before the session on one 14-core Windows laptop. Use these for orders of magnitude, not as package rankings.

| | Comparison | Time | Memory |
|---|---|---|---|
| A | Read the same 1.2 GB CSV: `readr::read_csv()` vs `data.table::fread()` | 102 s vs 1.2 s | similar |
| B | Same in-memory aggregation: dplyr vs data.table | 2.2 s vs 2.5 s | **2.6 GB vs 0.45 GB** allocated |
| C | data.table, **January** from CSV (20M rows) | 2.2 s | 2.1 GB peak |
| C | Arrow, **whole year** from Parquet (240M rows) | 17 s | 1.3 GB peak |
| C | DuckDB, **whole year** from Parquet (240M rows) | **2.5 s** | **1.1 GB** peak |

What to take from them:

- **A.** About 90% of readr's time here is spent parsing the two datetime columns. readr also guessed the integer zone IDs as doubles, so its table was 1.3 GB against fread's 0.8 GB. **Declare column types when you read large files.**
- **B.** The speed was the same, but the memory was not. On a shared VM, memory is usually the binding constraint.
- **C.** Changing *where* the work happens (a database engine over an efficient file format) handled twelve times the data in about the time, and about half the memory, of reading one month into R. That matters more than making in-memory code slightly faster.

`object.size()` and `bench::mark(memory = TRUE)` only see memory allocated by R. Arrow, DuckDB and database drivers use memory outside R, which is why section C measures the whole process.

## 5. Combining linked data safely

*Script step 4.*

❓ *Before joining, should this return any rows?*

```r
daily_zone[, .N, by = .(PULocationID, pickup_date)][N > 1]   # 0 rows
```

(This check cannot fail straight after a `by` aggregation. It matters when the table comes from a file, a colleague or someone else's SQL.)

State the expectation (many zone-days → one zone), join, and check that the expectation held:

```r
n_before <- nrow(daily_zone)
analysis <- merge(daily_zone, zones, by.x = "PULocationID", by.y = "LocationID", all.x = TRUE)
nrow(analysis) == n_before                # TRUE
analysis[is.na(Zone), unique(PULocationID)]   # no unmatched IDs
```

### A wrong join that succeeds

Suppose a second source is keyed by zone *name*:

```r
analysis_bad <- merge(analysis, zones[, .(Zone, service_zone)], by = "Zone")
nrow(analysis_bad)                                       # 8,072, not 8,006
analysis_bad[, sum(n_trips)] - analysis[, sum(n_trips)]  # 61,440 trips that never happened
```

There is no error and no warning. ❓ *Would R know this was wrong?* No. Make your expectation executable:

- **dplyr:** `left_join(x, y, by = ..., relationship = "many-to-one")` stops with an error if it is violated (see [`code/02_workflow_dplyr.R`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/code/02_workflow_dplyr.R)).
- **data.table / base R:** `stopifnot(nrow(after) == nrow(before))`, and check the total of a count column before and after.

> **Key point:** code running without an error doesn't mean the join was right.

## 6. Missingness, structural zeroes and validation

*Script step 5.*

❓ *If a zone-day doesn't appear in `daily_zone`, have we shown that zero trips happened?*

Build the intended **observation frame** (every zone × every day) and see what is missing:

```r
zone_days <- CJ(PULocationID = zones$LocationID,
                pickup_date  = seq(as.IDate("2024-01-01"), as.IDate("2024-01-31"), by = "day"))
analysis_complete <- merge(zone_days, daily_zone, by = c("PULocationID", "pickup_date"), all.x = TRUE)
analysis_complete[is.na(n_trips), .N, by = PULocationID]
```

209 of the 8,215 zone-days have no record:

| ID | Zone | Days with no record | What might it mean? |
|---|---|---|---|
| 1 | Newark Airport | 30 | Out-of-state airport; pickups rare |
| 2 | Jamaica Bay | 17 | Mostly water and parkland |
| 103–105 | Governor's / Ellis / Liberty Island | 31, 31, 29 | No public road access: plausibly true zeroes |
| 110 | Great Kills Park | 14 | Park |
| 199 | Rikers Island | 26 | Jail: restricted access |
| 264 | "Unknown" | 31 | **Not a place.** It shouldn't be in the frame. |

❓ *Should we run `analysis_complete[is.na(n_trips), n_trips := 0L]`?* Only with reasons you can write down:

- Was the unit genuinely under observation (frame coverage)?
- Are the source submissions complete for the period?
- Does the absence of a record mean the absence of an event?
- Could linkage or processing upstream have dropped records?

❓ **SRS question.** *A school has no exclusions recorded for one term. Is that zero exclusions? What would you check first?*

Not necessarily. Check whether the school sent its return that term, whether it was open and in scope, and whether pupil records could have failed to link. Ask yourself how the data would look different if the school simply hadn't sent anything: often, they'd look exactly the same.

> **Key point:** a missing value doesn't mean anything on its own. What it means depends on how the data were collected.

### Validation (more than there was time for live)

**Check events before aggregating**, while the detail still exists (*script step 2*). Or run the checks in the database, where the source always remains:

```r
trips_db |>
  filter(pickup_datetime < "2024-02-01") |>
  summarise(negative_fare = sum(as.integer(base_passenger_fare < 0), na.rm = TRUE),
            zero_miles    = sum(as.integer(trip_miles == 0), na.rm = TRUE),
            n             = n()) |>
  collect()
# 191 negative fares, 3,286 zero-mile trips, 19,663,930 trips
```

❓ *Do we delete the 191 negative fares?* No. Detection prompts investigation (refunds? adjustments? errors?). Then decide, document and count what you excluded.

**Conservation checks** catch silent losses. After aggregating, `sum(n_trips)` should equal the number of trips. After a left join onto a frame, the total should be unchanged. Both are in the script as `stopifnot()` lines.

**SQL and R treat missing values differently.** SQL aggregates (`AVG`, `SUM`, `MIN`, `MAX`) ignore NULLs, while R's `mean(c(1, NA))` is `NA`. The same-looking dplyr code can therefore mean different things in R and in the database; dbplyr warns about this once per session. Relatedly, `as.Date()` in dbplyr becomes `TRY_CAST`, which turns unconvertible values into NULL silently.

**Aggregation creates small cells.** 66 zone-days have fewer than 10 trips. In the SRS, every output goes through statistical disclosure control, so build suppression or rounding thresholds into the pipeline rather than discovering them at output checking.

## 7. Reproducible workflows

Comments should record **decisions and reasons**, not narrate syntax:

```r
# Weak:
# Calculate daily summary

# Useful:
# Collapse to zone-day before linkage: downstream models use zone-days,
# and the trip table will not fit in memory alongside the linked data.
```

Turn repeated checks into a function, so you write them once and every join gets the same treatment. This is the check from §5, made reusable:

```r
check_join <- function(before, after, count_col) {
  stopifnot(nrow(after) == nrow(before),
            sum(after[[count_col]]) == sum(before[[count_col]]))
  invisible(after)
}

check_join(daily_zone, analysis,     "n_trips")   # passes silently
check_join(daily_zone, analysis_bad, "n_trips")   # stops:
# Error in check_join(...) : nrow(after) == nrow(before) is not TRUE
```

The script now stops at the problem, instead of carrying on with 61,440 trips that never happened. Small functions that each do one job and get reused are what "modular code" means in practice.

The same goes for repeated decisions, so each decision lives in one place:

```r
read_trips <- function(path) {
  fread(path, select = c("pickup_datetime", "PULocationID", "trip_miles",
                         "trip_time", "base_passenger_fare"))
}
```

Structure the project as a pipeline: numbered scripts that each read the previous stage's saved output. This repository is a small example:

```
00 download & reduce  →  saved intermediate  →  link & validate  →  analysis
```

And make sure R never restores a saved workspace. In RStudio: *Tools → Global Options → General → Workspace*: untick "Restore .RData" and set "Save workspace" to **Never**. If your analysis only works because of objects left over in `.RData`, it isn't reproducible.

❓ *Which assumptions that began in your head are now visible or testable in the code?* The analytical unit, the time window, the columns kept, the aggregation rule, join keys and cardinality, the observation frame, and the QA expectations.

> **Key point:** reproducible doesn't just mean it runs twice. It means your assumptions are written down, and checked where you can.

## 8. Reflect on your own workflow

Pick one step in your own SRS or TRE work that is slow, memory-hungry, hard to rerun, prone to duplicates, hard to validate, or reliant on an assumption about missing records. Work through the [seven questions](#seven-questions-for-any-step-in-a-workflow) below. What would you change first?

---

## Check your understanding

Answer each question before opening the answer. They're designed for new situations, not this dataset.

**1.** A dataset has one row per GP consultation. Your question is about how many children in each local authority were seen at least once per school year. What is the source unit, and what is the analytical unit?

<details markdown="1"><summary>Answer</summary>

Source unit: a consultation. Analytical unit: local authority × school year (via child × school year, to count children rather than consultations). Several consultations per child must collapse before counting, or children with many visits are counted many times.
</details>

**2.** Which of these does the reduction inside the database?

```r
# A
tbl(con, "pupils") |> filter(year == 2019) |> select(pupil_id, fsm) |> collect()
# B
tbl(con, "pupils") |> collect() |> filter(year == 2019) |> select(pupil_id, fsm)
```

<details markdown="1"><summary>Answer</summary>

**A.** The filter and column selection run in the database, and only 2019's two columns come back. B calls `collect()` first, so every row and column of the table is copied into R before anything is cut down.
</details>

**3.** Save once, or rerun each time? (a) linking ten years of school census to hospital records; (b) a sensitivity analysis with a different covariate set; (c) recoding ethnicity into five groups you are still deciding on.

<details markdown="1"><summary>Answer</summary>

(a) **Save**: expensive and stable. (b) **Rerun**: cheap and changing. (c) **Rerun**: it's still changing. Save the stable linked data *before* the recode, so you can change the recode cheaply.
</details>

**4.** You join a pupil-year table (one row per pupil per year) to a school lookup on the school's URN. What relationship do you expect, and what two checks would you write?

<details markdown="1"><summary>Answer</summary>

Many-to-one (many pupil-years to one school). Check that the URN is unique in the lookup *before* joining, and that the row count is unchanged *after* (or use `relationship = "many-to-one"` in dplyr). Checking for unmatched URNs is a useful third.
</details>

**5.** After linking, some local-authority × month cells have no emergency admissions recorded. Name two things you would want to know before treating them as zero.

<details markdown="1"><summary>Answer</summary>

Any two of: whether every provider submitted data for that month (completeness); whether the local authority was in scope for that period (boundary or coverage changes); whether records could have failed to link and been dropped; whether "no record" really means "no event" for this data source.
</details>

**6.** Your script contains `df <- df[df$age < 25, ]` with no comment. What assumption is hidden, and how would you make it visible?

<details markdown="1"><summary>Answer</summary>

Why the cut-off is 25, and whether it applies at a particular date, are both hidden. Name it (`max_age <- 25`), explain the reason in a comment, and consider a check, such as counting and reporting how many rows were excluded.
</details>

---

## Quick reference

### Seven questions for any step in a workflow

1. **What's one row?** In the source, and in every table you make.
2. **What should one row be, for my question?**
3. **Could I cut rows, columns or detail earlier, or in the database?**
4. **Am I repeating slow work** that I could do once and save?
5. **What should this join do, and am I checking it?**
6. **What does a missing record mean here?** A real zero, not observed, or lost along the way?
7. **How would I know if this step went wrong?**

### Patterns side by side

| Task | data.table | dplyr | SQL (via dbplyr) |
|---|---|---|---|
| Keep rows | `DT[year == 2024]` | `filter(df, year == 2024)` | `WHERE year = 2024` |
| Keep columns | `fread(f, select = cols)` | `select(df, all_of(cols))` | `SELECT col1, col2` |
| Add a column | `DT[, d := as.IDate(t)]` | `mutate(df, d = as.Date(t))` | `CAST(t AS DATE) AS d` |
| Aggregate | `DT[, .(n = .N), by = .(id, d)]` | `count(df, id, d)` | `GROUP BY id, d` |
| Is a key unique? | `DT[, .N, by = id][N > 1]` | `count(df, id) \|> filter(n > 1)` | `GROUP BY id HAVING COUNT(*) > 1` |
| Guarded join | `merge(...)` + `stopifnot(nrow(...) == n_before)` | `left_join(..., relationship = "many-to-one")` | compare counts before and after |
| Complete frame | `CJ(id = ids, d = dates)` | `tidyr::crossing(id = ids, d = dates)` | build, then join |
| Save an intermediate | `saveRDS(x, "derived/x.rds")` | `saveRDS(x, "derived/x.rds")` | `compute(q)` (table in the database) |

### Further reading

- `vignette("datatable-intro", package = "data.table")`
- dbplyr: <https://dbplyr.tidyverse.org/>
- Arrow datasets in R: <https://arrow.apache.org/docs/r/articles/dataset.html>
- Join cardinality checks: `?dplyr::left_join` (`relationship`, `unmatched`)
- ONS Secure Research Service: <https://www.ons.gov.uk/aboutus/whatwedo/statistics/requestingstatistics/secureresearchservice>

---

## Setting up

You only need this if you want to run the code. You do **not** need SRS access.

1. **R ≥ 4.3** and, ideally, RStudio. Open `teaching.Rproj`: all paths are relative to the project folder.
2. **Packages:**
   ```r
   install.packages(c("data.table", "dplyr", "readr", "tidyr", "arrow",
                      "DBI", "dbplyr", "duckdb"))
   ```
3. **Data.** About 5.4 GB to download and ~7 GB on disk, from the NYC Taxi & Limousine Commission:
   ```r
   source("code/00_download_and_prepare.R")
   ```
   For a smaller download (January only, ~0.5 GB), run `Sys.setenv(HVFHV_N_MONTHS = "1")` first. Everything still works; the "whole year" scripts just use January.
4. **Memory.** The January examples need ~3 GB of free RAM. With less, read `data/fallback/fhvhv_2024-01_sample_250k.csv` instead; your counts will differ from these notes.
5. **Run the scripts in order:** `01_workflow_data_table.R` (or `02_workflow_dplyr.R`), then `03_full_year_arrow.R` and `04_database_dbplyr.R`. On a recent laptop they take roughly 5 s, 1 min, 20–40 s and 5 s respectively (the first run of a script is slower while files are read from disk). The dplyr version is slower because parsing datetimes from CSV is slow, which is itself a lesson.

**Things to know:**

- Your counts should match these notes exactly if the TLC hasn't republished the files. Compare the checksums in [`data/MANIFEST.csv`](https://github.com/yangjustinc/good-practice-r-ons-srs/blob/main/data/MANIFEST.csv) with `tools::md5sum()`. Timings will differ on your machine.
- Timestamps are New York local time, stored without a time zone. After the CSV step R labels them "UTC"; the clock times and dates are correct, so don't convert them.
- **Before using any of this in the SRS**, check which packages are available in your environment, and follow your project's output-checking rules. Nothing here needs to leave or enter the SRS: the techniques transfer, not the data.
