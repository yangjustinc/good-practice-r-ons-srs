# Good Practice for R Users When Working in the ONS SRS
# 01 — THE WORKFLOW IN data.table (complete worked example)
#
# The complete version of what the session built live, with every
# expectation written as an executable check. Run from the project root.
#
# Source unit: trip.  Analytical unit: pickup zone x day.  January 2024.

if (!file.exists("teaching.Rproj")) stop("Run from the project root.")

library(data.table)

dir.create("derived", showWarnings = FALSE)

jan_file  <- "data/teaching_csv/fhvhv_tripdata_2024-01_selected.csv"
zone_file <- "data/lookup/taxi_zone_lookup.csv"

study_start <- as.IDate("2024-01-01")
study_end   <- as.IDate("2024-01-31")

# -------------------------------------------------------------------------
# 1. Read and derive (event level)
# -------------------------------------------------------------------------

# Read only the columns this analysis uses (rows, COLUMNS, granularity).
cols_used <- c("pickup_datetime", "PULocationID", "trip_miles",
               "trip_time", "base_passenger_fare")

trips <- fread(jan_file, select = cols_used)

cat("Trip rows:       ", format(nrow(trips), big.mark = ","), "\n")
cat("Trip object size:", format(object.size(trips), units = "GB"), "\n")

trips[, pickup_date := as.IDate(pickup_datetime)]
trips[, trip_minutes := trip_time / 60]   # trip_time is in seconds

# -------------------------------------------------------------------------
# 2. Event-level QA: run BEFORE aggregation discards the detail
# -------------------------------------------------------------------------

qa_trip <- trips[, .(
  rows                = .N,
  outside_study_dates = sum(pickup_date < study_start | pickup_date > study_end),
  negative_miles      = sum(trip_miles < 0, na.rm = TRUE),
  negative_time       = sum(trip_time < 0, na.rm = TRUE),
  negative_fare       = sum(base_passenger_fare < 0, na.rm = TRUE),
  zero_miles          = sum(trip_miles == 0, na.rm = TRUE),
  missing_pickup_zone = sum(is.na(PULocationID))
)]
print(qa_trip)

# Unusual values are reported, not silently dropped. Excluding them would
# be an analytical decision that should be made, documented and counted
# explicitly.
stopifnot(qa_trip$outside_study_dates == 0L)

# -------------------------------------------------------------------------
# 3. Reduce granularity: trip -> zone-day
# -------------------------------------------------------------------------

# Collapse to pickup-zone/day before linkage: downstream analyses use
# zone-days as the analytical unit, and the trip table need not persist.
daily_zone <- trips[
  ,
  .(
    n_trips           = .N,
    mean_trip_miles   = mean(trip_miles, na.rm = TRUE),
    mean_trip_minutes = mean(trip_minutes, na.rm = TRUE),
    mean_base_fare    = mean(base_passenger_fare, na.rm = TRUE)
  ),
  by = .(PULocationID, pickup_date)
]

# Conservation check: aggregation must not gain or lose trips.
stopifnot(daily_zone[, sum(n_trips)] == nrow(trips))

cat("Zone-day rows:       ", format(nrow(daily_zone), big.mark = ","), "\n")
cat("Zone-day object size:", format(object.size(daily_zone), units = "MB"), "\n")

saveRDS(daily_zone, "derived/hvfhv_zone_day_2024_01_data_table.rds")

n_trips_total <- nrow(trips)
rm(trips)
invisible(gc())

# -------------------------------------------------------------------------
# 4. Link the zone lookup (expected: many zone-days -> one zone)
# -------------------------------------------------------------------------

zones <- fread(zone_file)

# Keys must be unique on the "one" side and on the analytical unit.
stopifnot(
  zones[, .N, by = LocationID][N > 1, .N] == 0L,
  daily_zone[, .N, by = .(PULocationID, pickup_date)][N > 1, .N] == 0L
)

# Zone NAMES are not unique, so they must never be used as a join key.
cat("Zone names used by more than one LocationID:\n")
print(zones[, .(n_ids = .N, ids = toString(LocationID)), by = Zone][n_ids > 1])

n_before <- nrow(daily_zone)

analysis <- merge(
  daily_zone, zones,
  by.x = "PULocationID", by.y = "LocationID",
  all.x = TRUE
)

stopifnot(
  nrow(analysis) == n_before,
  analysis[, sum(n_trips)] == n_trips_total,
  analysis[, .N, by = .(PULocationID, pickup_date)][N > 1, .N] == 0L
)

unmatched_zone_ids <- analysis[is.na(Zone), unique(PULocationID)]
cat("Unmatched pickup-zone IDs:", if (length(unmatched_zone_ids)) unmatched_zone_ids else "none", "\n")

# -------------------------------------------------------------------------
# 5. Observation frame: absence of a row is not (yet) a zero
# -------------------------------------------------------------------------

zone_days <- CJ(
  PULocationID = zones$LocationID,
  pickup_date  = seq(study_start, study_end, by = "day")
)

analysis_complete <- merge(
  zone_days, daily_zone,
  by = c("PULocationID", "pickup_date"),
  all.x = TRUE
)

# Every observed zone-day must fall inside the frame; otherwise the left
# join would silently drop trips.
stopifnot(analysis_complete[, sum(n_trips, na.rm = TRUE)] == n_trips_total)

analysis_complete <- merge(
  analysis_complete, zones,
  by.x = "PULocationID", by.y = "LocationID",
  all.x = TRUE
)

cat("Complete zone-day frame rows:", format(nrow(analysis_complete), big.mark = ","), "\n")
cat("Zone-days with no trip record, by zone:\n")
print(analysis_complete[is.na(n_trips), .(zone_days = .N), by = .(PULocationID, Borough, Zone)])

# Deliberately NOT replacing NA with 0. Some of these are plausible true
# zeroes (islands without road access); LocationID 264 ("Unknown") and
# 265 ("Outside of NYC") are not places in NYC at all, which suggests the
# observation frame itself needs a decision.

# Disclosure planning: small cells appear at aggregation time.
cat("Zone-days with fewer than 10 trips:", daily_zone[n_trips < 10, .N], "\n")

saveRDS(analysis_complete, "derived/hvfhv_analysis_complete_2024_01_data_table.rds")
