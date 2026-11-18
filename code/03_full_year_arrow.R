# Good Practice for R Users When Working in the ONS SRS
# 03 — ARROW: THE FULL YEAR WITHOUT LOADING IT
#
# A DIFFERENT computational model from scripts 01 and 02:
#   01 / 02 (in memory): read January into memory, then transform it.
#   Arrow:               treat all monthly Parquet files as ONE dataset,
#                        describe the reduction lazily, and collect only
#                        the small zone-day result.
#
# This is not evidence that "Arrow is faster than data.table": the storage
# format, I/O, execution engine and memory model all differ.
#
# SRS relevance: useful when extracts are supplied as Parquet, or when you
# can write a large intermediate to Parquet once and query it repeatedly.
# Check that the arrow package is available in your SRS environment.

if (!file.exists("teaching.Rproj")) stop("Run from the project root.")

library(arrow)
library(dplyr)

dir.create("derived", showWarnings = FALSE)

dataset <- open_dataset("data/raw_parquet", format = "parquet")

# Printing shows the schema (24 columns) and the files. No rows are read.
print(dataset)

# Row count from Parquet metadata, without reading the data.
cat("Source rows (all months):", format(nrow(dataset), big.mark = ","), "\n")

# Describe the query. Nothing runs yet.
daily_zone_query <- dataset |>
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

class(daily_zone_query)   # a query description, not data

# collect() runs the query and returns only the reduced result to R.
daily_zone_arrow <- collect(daily_zone_query)

stopifnot(sum(daily_zone_arrow$n_trips) == nrow(dataset))

cat("Collected rows:        ", format(nrow(daily_zone_arrow), big.mark = ","), "\n")
cat("Collected object size: ", format(object.size(daily_zone_arrow), units = "MB"), "\n")
cat("Date range:            ", format(range(daily_zone_arrow$pickup_date)), "\n")

# Arrow's working memory is allocated outside R, so object.size() and
# bench::mark(memory = TRUE) cannot see it. Ask Arrow directly:
cat("Arrow peak memory pool:",
    round(default_memory_pool()$max_memory / 1024^2), "MB\n")

saveRDS(daily_zone_arrow, "derived/hvfhv_zone_day_2024_full_year_arrow.rds")
