# Good Practice for R Users When Working in the ONS SRS
# 04 — LET THE DATABASE DO THE WORK: DBI + dbplyr
#
# In the SRS, source data often sit in SQL Server tables, accessed from R
# through DBI + odbc. The most important efficiency decision is then WHERE
# the filtering, selecting and aggregation run:
#
#   BAD:   pull the table into R, then reduce it in R
#   GOOD:  describe the reduction in R, let dbplyr translate it to SQL,
#          let the database run it, and collect() only the result
#
# No SQL Server is needed to learn this. DuckDB is an in-process database
# that can query our Parquet files directly through the SAME DBI/dbplyr
# interface. Only the dbConnect() line differs.
#
# Packages: DBI, dplyr, dbplyr, duckdb

if (!file.exists("teaching.Rproj")) stop("Run from the project root.")

library(DBI)
library(dplyr)
library(dbplyr)

# -------------------------------------------------------------------------
# 1. Connect
# -------------------------------------------------------------------------

con <- dbConnect(duckdb::duckdb())

# A view over every monthly Parquet file: one "table" of ~240 million rows,
# of which nothing has been read yet.
dbExecute(con, "
  CREATE VIEW hvfhv AS
  SELECT * FROM read_parquet('data/raw_parquet/*.parquet')
")

# In the SRS, the equivalent would be something like:
#   con <- dbConnect(
#     odbc::odbc(),
#     Driver             = "SQL Server",   # or "ODBC Driver 17/18 for SQL Server"
#     Server             = "<server name>",
#     Database           = "<project database>",
#     Trusted_Connection = "Yes"
#   )
#   trips_db <- tbl(con, I("dbo.<table name>"))   # dbplyr >= 2.4; or in_schema("dbo", "<table>")
# Ask your SRS support team for the exact driver/server/database names.

trips_db <- tbl(con, "hvfhv")
trips_db   # "?? rows": R has not counted them because it has not looked

# -------------------------------------------------------------------------
# 2. Describe the reduction lazily
# -------------------------------------------------------------------------

daily_zone_db <- trips_db |>
  filter(pickup_datetime >= "2024-01-01", pickup_datetime < "2024-02-01") |>
  select(pickup_datetime, PULocationID, trip_miles, trip_time, base_passenger_fare) |>
  mutate(pickup_date = as.Date(pickup_datetime)) |>
  group_by(PULocationID, pickup_date) |>
  summarise(
    n_trips           = n(),
    mean_trip_miles   = mean(trip_miles, na.rm = TRUE),
    mean_trip_minutes = mean(trip_time, na.rm = TRUE) / 60,
    mean_base_fare    = mean(base_passenger_fare, na.rm = TRUE),
    .groups = "drop"
  )

# The SQL that will run in the database:
show_query(daily_zone_db)

# The same pipeline as SQL Server (T-SQL) would receive it, generated
# without any server. Useful for checking what your SRS code sends.
lazy_frame(
  pickup_datetime = Sys.time(), PULocationID = 1L, trip_miles = 1,
  trip_time = 1L, base_passenger_fare = 1,
  con = simulate_mssql()
) |>
  filter(pickup_datetime >= "2024-01-01", pickup_datetime < "2024-02-01") |>
  mutate(pickup_date = as.Date(pickup_datetime)) |>
  group_by(PULocationID, pickup_date) |>
  summarise(n_trips = n(), mean_base_fare = mean(base_passenger_fare, na.rm = TRUE),
            .groups = "drop") |>
  show_query()

# -------------------------------------------------------------------------
# 3. Collect only the result
# -------------------------------------------------------------------------

t <- system.time(daily_zone <- collect(daily_zone_db))
cat("Collected", format(nrow(daily_zone), big.mark = ","), "zone-day rows in",
    round(t[["elapsed"]], 2), "seconds\n")

# Cross-check against the in-memory data.table result, if it exists.
dt_file <- "derived/hvfhv_zone_day_2024_01_data_table.rds"
if (file.exists(dt_file)) {
  dt <- readRDS(dt_file)
  same <- nrow(dt) == nrow(daily_zone) && sum(dt$n_trips) == sum(daily_zone$n_trips)
  cat("Matches data.table result:", same, "\n")
}

# -------------------------------------------------------------------------
# 4. Validation queries can also run in the database
# -------------------------------------------------------------------------

trips_db |>
  filter(pickup_datetime >= "2024-01-01", pickup_datetime < "2024-02-01") |>
  summarise(
    rows          = n(),
    negative_fare = sum(as.integer(base_passenger_fare < 0), na.rm = TRUE),
    zero_miles    = sum(as.integer(trip_miles == 0), na.rm = TRUE),
    missing_zone  = sum(as.integer(is.na(PULocationID)), na.rm = TRUE),
    first_pickup  = min(pickup_datetime, na.rm = TRUE),
    last_pickup   = max(pickup_datetime, na.rm = TRUE)
  ) |>
  collect() |>
  print(width = Inf)

# -------------------------------------------------------------------------
# Pitfalls worth knowing in the SRS
# -------------------------------------------------------------------------
#
# * collect() too early:
#     trips_db |> collect() |> filter(...)    # pulls EVERY row into R
#   Keep the pipeline lazy until the result is small.
#
# * Missing-data semantics differ. SQL aggregates (AVG, SUM, MIN, MAX)
#   ignore NULLs, whereas in R mean(c(1, NA)) is NA. dbplyr warns once
#   per session; na.rm = TRUE silences it but changes nothing in SQL.
#
# * as.Date() becomes TRY_CAST(... AS DATE): values that fail to convert
#   become NULL silently. Count NULLs after conversion.
#
# * Not every R function has a SQL translation. If dbplyr cannot translate
#   one, it passes it through verbatim and the database errors. Use
#   show_query() to see what will run.
#
# * Use compute() to materialise a reusable intermediate as a temporary
#   table INSIDE the database, rather than collecting and re-uploading.

dbDisconnect(con, shutdown = TRUE)
