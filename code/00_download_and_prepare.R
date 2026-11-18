# Good Practice for R Users When Working in the ONS SRS
# 00 — PRE-SESSION DATA ACQUISITION AND PREPARATION
#
# Run ONCE, before teaching, from the project root
# (open teaching.Rproj, then source("code/00_download_and_prepare.R")).
#
# Worked dataset
#   NYC Taxi & Limousine Commission (TLC) High Volume For-Hire Vehicle
#   (HVFHV) trip records, 2024.
#   Source: https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
#   Data dictionary: "High Volume FHV Trip Records" on the same page.
#
# Why this dataset?
#   It is public, event-level, and genuinely large: ~20 million trips per
#   month, ~240 million in 2024, published as monthly Parquet files. It has
#   the same structural problems as administrative data (events below the
#   analytical unit, coded identifiers, a lookup table, missing records),
#   without any disclosure risk.
#
# What this script does
#   1. downloads the monthly 2024 HVFHV Parquet files (~5.4 GB for 12);
#   2. downloads the official taxi-zone lookup;
#   3. writes a seven-column January CSV (~1.2 GB) for the in-memory
#      data.table / dplyr part of the lesson;
#   4. writes a 250,000-row fallback CSV for low-memory machines;
#   5. writes data/MANIFEST.csv (file sizes + MD5 checksums), so you can
#      tell later exactly which version of each file you used. The TLC
#      occasionally republishes files.
#
# Low-bandwidth option
#   Set HVFHV_N_MONTHS before running to download fewer months, e.g.
#     Sys.setenv(HVFHV_N_MONTHS = "1")   # January only (~0.5 GB)
#   The Arrow/DuckDB "full-year" scripts then use whatever months exist.
#
# Note on timestamps
#   TLC timestamps are New York local time stored WITHOUT a time zone.
#   After the CSV round trip, fread() labels them "UTC". The clock times
#   (and therefore the dates) are correct; just do not convert them to
#   another time zone.
#
# Packages: arrow, data.table

if (!file.exists("teaching.Rproj")) {
  stop("Run this from the project root: open teaching.Rproj first.")
}

library(arrow)
library(data.table)

# Large files: R's default 60-second download timeout is far too short.
options(timeout = max(3600, getOption("timeout")))

for (d in c("data/raw_parquet", "data/teaching_csv", "data/lookup",
            "data/fallback", "derived")) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

year <- 2024L
n_months <- as.integer(Sys.getenv("HVFHV_N_MONTHS", "12"))
stopifnot(n_months %in% 1:12)
months <- sprintf("%02d", seq_len(n_months))

base_url <- "https://d37ci6vzurychx.cloudfront.net"

trip_urls <- sprintf("%s/trip-data/fhvhv_tripdata_%d-%s.parquet",
                     base_url, year, months)
trip_files <- file.path("data/raw_parquet",
                        sprintf("fhvhv_tripdata_%d-%s.parquet", year, months))

zone_url <- paste0(base_url, "/misc/taxi_zone_lookup.csv")
zone_file <- "data/lookup/taxi_zone_lookup.csv"

# Download to a temporary name and rename only on success, so an
# interrupted download is never mistaken for a complete file.
download_if_missing <- function(url, dest) {
  if (file.exists(dest)) {
    message("Already present: ", dest)
    return(invisible(dest))
  }
  message("Downloading: ", basename(dest))
  tmp <- paste0(dest, ".part")
  on.exit(unlink(tmp), add = TRUE)
  status <- download.file(url, destfile = tmp, mode = "wb", quiet = FALSE)
  if (status != 0L) stop("Download failed: ", url)
  file.rename(tmp, dest)
  invisible(dest)
}

invisible(Map(download_if_missing, trip_urls, trip_files))
download_if_missing(zone_url, zone_file)

# The seven fields used in the lesson (the source has 24).
cols_needed <- c(
  "pickup_datetime",
  "dropoff_datetime",
  "PULocationID",
  "DOLocationID",
  "trip_miles",
  "trip_time",            # seconds
  "base_passenger_fare"   # US dollars, before tolls/taxes/fees/tips
)

# -------------------------------------------------------------------------
# Reduced January CSV + fallback sample (one read of January)
# -------------------------------------------------------------------------

jan_parquet <- trip_files[1]
jan_csv <- "data/teaching_csv/fhvhv_tripdata_2024-01_selected.csv"
fallback_csv <- "data/fallback/fhvhv_2024-01_sample_250k.csv"

if (!file.exists(jan_csv) || !file.exists(fallback_csv)) {
  message("Reading January (selected columns only)...")

  # Reading only the needed columns from Parquet is itself one of the
  # lesson's principles: the full 24-column file is never in memory.
  jan <- as.data.table(read_parquet(jan_parquet, col_select = all_of(cols_needed)))

  if (!file.exists(jan_csv)) {
    message("Writing ", jan_csv)
    fwrite(jan, jan_csv)
  }

  if (!file.exists(fallback_csv)) {
    message("Writing ", fallback_csv)
    set.seed(20261125)
    fwrite(jan[sample.int(.N, min(250000L, .N))], fallback_csv)
  }

  rm(jan)
  invisible(gc())
}

# -------------------------------------------------------------------------
# Provenance manifest
# -------------------------------------------------------------------------

all_files <- c(trip_files, zone_file)
manifest <- data.table(
  file       = all_files,
  source_url = c(trip_urls, zone_url),
  size_bytes = file.size(all_files),
  md5        = unname(tools::md5sum(all_files)),
  file_date  = format(file.mtime(all_files), "%Y-%m-%d")
)
fwrite(manifest, "data/MANIFEST.csv")

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------

zones <- fread(zone_file)

# nrow() on an Arrow Dataset reads Parquet metadata, not the data itself.
jan_rows  <- nrow(open_dataset(jan_parquet))
year_rows <- nrow(open_dataset("data/raw_parquet", format = "parquet"))

cat("\n============================================================\n")
cat("PREPARATION COMPLETE\n")
cat("============================================================\n")
cat("Parquet files:          ", length(trip_files), "\n")
cat("Total Parquet size:     ", round(sum(file.size(trip_files)) / 1024^3, 2), "GB\n")
cat("January teaching CSV:   ", round(file.size(jan_csv) / 1024^3, 2), "GB\n")
cat("January rows:           ", format(jan_rows, big.mark = ","), "\n")
cat("Rows across all months: ", format(year_rows, big.mark = ","), "\n")
cat("Taxi-zone lookup rows:  ", nrow(zones), "\n")
cat("Duplicate LocationIDs:  ", zones[, .N, by = LocationID][N > 1, .N], "\n")
cat("Manifest written to:     data/MANIFEST.csv\n\n")
