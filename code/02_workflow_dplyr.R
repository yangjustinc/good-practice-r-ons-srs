# Good Practice for R Users When Working in the ONS SRS
# 02 — THE SAME WORKFLOW IN dplyr ("Rosetta Stone")
#
# The same January analysis as 01_workflow_data_table.R in tidyverse
# syntax, for participants who think in dplyr. The good-practice points
# are package-independent; only the syntax changes.
#
# One dplyr advantage worth knowing: the `relationship` argument to joins
# (dplyr >= 1.1.0) makes your expected cardinality executable.

if (!file.exists("teaching.Rproj")) stop("Run from the project root.")

library(dplyr)
library(readr)
library(tidyr)

dir.create("derived", showWarnings = FALSE)

jan_file  <- "data/teaching_csv/fhvhv_tripdata_2024-01_selected.csv"
zone_file <- "data/lookup/taxi_zone_lookup.csv"

study_start <- as.Date("2024-01-01")
study_end   <- as.Date("2024-01-31")

# 1. Read and derive -------------------------------------------------------

# Read only the columns this analysis uses, and declare their types:
# readr would otherwise guess the integer IDs as doubles (more memory), and
# parsing each datetime column is the slowest part of reading this file.
trips <- read_csv(
  jan_file,
  col_select = c(pickup_datetime, PULocationID, trip_miles,
                 trip_time, base_passenger_fare),
  col_types  = cols(
    pickup_datetime     = col_datetime(),
    PULocationID        = col_integer(),
    trip_miles          = col_double(),
    trip_time           = col_integer(),
    base_passenger_fare = col_double(),
    .default            = col_skip()
  )
) |>
  mutate(
    pickup_date  = as.Date(pickup_datetime),
    trip_minutes = trip_time / 60
  )

cat("Trip rows:       ", format(nrow(trips), big.mark = ","), "\n")
cat("Trip object size:", format(object.size(trips), units = "GB"), "\n")

# 2. Event-level QA --------------------------------------------------------

qa_trip <- trips |>
  summarise(
    rows                = n(),
    outside_study_dates = sum(pickup_date < study_start | pickup_date > study_end),
    negative_miles      = sum(trip_miles < 0, na.rm = TRUE),
    negative_time       = sum(trip_time < 0, na.rm = TRUE),
    negative_fare       = sum(base_passenger_fare < 0, na.rm = TRUE),
    zero_miles          = sum(trip_miles == 0, na.rm = TRUE),
    missing_pickup_zone = sum(is.na(PULocationID))
  )
print(qa_trip)
stopifnot(qa_trip$outside_study_dates == 0L)

# 3. Reduce granularity: trip -> zone-day ---------------------------------

daily_zone <- trips |>
  group_by(PULocationID, pickup_date) |>
  summarise(
    n_trips           = n(),
    mean_trip_miles   = mean(trip_miles, na.rm = TRUE),
    mean_trip_minutes = mean(trip_minutes, na.rm = TRUE),
    mean_base_fare    = mean(base_passenger_fare, na.rm = TRUE),
    .groups = "drop"
  )

stopifnot(sum(daily_zone$n_trips) == nrow(trips))

saveRDS(daily_zone, "derived/hvfhv_zone_day_2024_01_dplyr.rds")

n_trips_total <- nrow(trips)
rm(trips)
invisible(gc())

# 4. Link the zone lookup --------------------------------------------------

zones <- read_csv(zone_file, show_col_types = FALSE)

stopifnot(
  nrow(count(zones, LocationID) |> filter(n > 1)) == 0L,
  nrow(count(daily_zone, PULocationID, pickup_date) |> filter(n > 1)) == 0L
)

n_before <- nrow(daily_zone)

analysis <- daily_zone |>
  left_join(
    zones,
    by = c("PULocationID" = "LocationID"),
    relationship = "many-to-one"   # errors if the expectation is violated
  )

stopifnot(nrow(analysis) == n_before)

analysis |> filter(is.na(Zone)) |> distinct(PULocationID) |> print()

# What the relationship argument protects you from: joining on the
# non-unique zone NAME. Uncomment to see the error.
# analysis |>
#   left_join(select(zones, Zone, service_zone), by = "Zone",
#             relationship = "many-to-one")

# 5. Observation frame -----------------------------------------------------

zone_days <- crossing(
  PULocationID = zones$LocationID,
  pickup_date  = seq(study_start, study_end, by = "day")
)

analysis_complete <- zone_days |>
  left_join(daily_zone, by = c("PULocationID", "pickup_date"),
            relationship = "one-to-one")

stopifnot(sum(analysis_complete$n_trips, na.rm = TRUE) == n_trips_total)

analysis_complete <- analysis_complete |>
  left_join(zones, by = c("PULocationID" = "LocationID"),
            relationship = "many-to-one")

analysis_complete |>
  filter(is.na(n_trips)) |>
  count(PULocationID, Borough, Zone, name = "zone_days") |>
  print()

# Deliberately NOT replacing NA with 0 (see 01_workflow_data_table.R).

cat("Zone-days with fewer than 10 trips:", sum(daily_zone$n_trips < 10), "\n")

saveRDS(analysis_complete, "derived/hvfhv_analysis_complete_2024_01_dplyr.rds")
