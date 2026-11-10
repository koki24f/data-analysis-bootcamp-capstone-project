-- CityTransit analytics warehouse (SQLite)
-- Created by notebooks/05_database_bonus.ipynb. Safe to run repeatedly.
-- SQLite has no DATE type: dates are stored as ISO-8601 text (YYYY-MM-DD).

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------- aggregates

CREATE TABLE IF NOT EXISTS agg_ridership_by_month (
    year_month            TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    total_revenue         REAL    NOT NULL,
    unique_cards          INTEGER NOT NULL,
    avg_daily_boardings   REAL    NOT NULL,
    month_start           TEXT    NOT NULL,
    boardings_mom_growth  REAL,                       -- NULL for the first month
    PRIMARY KEY (year_month)
);

CREATE TABLE IF NOT EXISTS agg_ridership_by_hour (
    hour                  INTEGER NOT NULL CHECK (hour BETWEEN 0 AND 23),
    day_type              TEXT    NOT NULL CHECK (day_type IN ('Weekday', 'Weekend')),
    total_boardings       INTEGER NOT NULL,
    avg_boardings_per_day REAL    NOT NULL,
    pct_of_daily_total    REAL    NOT NULL,
    PRIMARY KEY (hour, day_type)
);

CREATE TABLE IF NOT EXISTS agg_route_performance (
    route_id              TEXT    NOT NULL,
    route_name            TEXT    NOT NULL,
    mode                  TEXT    NOT NULL,
    district              TEXT    NOT NULL,
    year_month            TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    total_revenue         REAL    NOT NULL,
    boardings_per_km      REAL    NOT NULL,
    avg_load_factor       REAL    NOT NULL,
    month_start           TEXT    NOT NULL,
    route_length_km       REAL    NOT NULL,
    PRIMARY KEY (route_id, year_month)
);

CREATE TABLE IF NOT EXISTS agg_mode_summary (
    mode                  TEXT    NOT NULL,
    year_month            TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    total_revenue         REAL    NOT NULL,
    route_count           INTEGER NOT NULL,
    boardings_per_route   REAL    NOT NULL,
    boardings_mom_growth  REAL,                       -- NULL for the first month
    month_start           TEXT    NOT NULL,
    PRIMARY KEY (mode, year_month)
);

CREATE TABLE IF NOT EXISTS agg_fare_type_mix (
    fare_type                 TEXT    NOT NULL,
    year_month                TEXT    NOT NULL,
    boardings                 INTEGER NOT NULL,
    revenue                   REAL    NOT NULL,
    pct_of_monthly_boardings  REAL    NOT NULL,
    month_start               TEXT    NOT NULL,
    PRIMARY KEY (fare_type, year_month)
);

CREATE TABLE IF NOT EXISTS agg_stop_activity (
    stop_id               TEXT    NOT NULL,
    stop_name             TEXT    NOT NULL,
    district              TEXT    NOT NULL,
    zone                  TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    rank_within_district  INTEGER NOT NULL,
    has_shelter           INTEGER NOT NULL CHECK (has_shelter IN (0, 1)),
    PRIMARY KEY (stop_id)
);

CREATE TABLE IF NOT EXISTS agg_vehicle_utilisation (
    vehicle_id            TEXT    NOT NULL,
    vehicle_type          TEXT    NOT NULL,
    depot                 TEXT    NOT NULL,
    vehicle_age_band      TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    avg_load_factor       REAL    NOT NULL,
    active_days           INTEGER NOT NULL,
    capacity              INTEGER NOT NULL,
    PRIMARY KEY (vehicle_id)
);

CREATE TABLE IF NOT EXISTS agg_peak_analysis (
    time_period           TEXT    NOT NULL,
    mode                  TEXT    NOT NULL,
    total_boardings       INTEGER NOT NULL,
    avg_load_factor       REAL    NOT NULL,
    pct_of_mode_total     REAL    NOT NULL,
    period_order          INTEGER NOT NULL,
    PRIMARY KEY (time_period, mode)
);

CREATE TABLE IF NOT EXISTS agg_transfer_behaviour (
    year_month            TEXT    NOT NULL,
    mode                  TEXT    NOT NULL,
    transfer_count        INTEGER NOT NULL,
    transfer_rate         REAL    NOT NULL,
    month_start           TEXT    NOT NULL,
    validations           INTEGER NOT NULL,
    PRIMARY KEY (year_month, mode)
);

-- ---------------------------------------------------------------- audit

CREATE TABLE IF NOT EXISTS pipeline_runs (
    run_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at     TEXT NOT NULL,
    finished_at    TEXT,
    status         TEXT NOT NULL CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED')),
    error_message  TEXT
);

CREATE TABLE IF NOT EXISTS pipeline_run_tables (
    run_id        INTEGER NOT NULL REFERENCES pipeline_runs (run_id),
    table_name    TEXT    NOT NULL,
    rows_written  INTEGER NOT NULL,
    PRIMARY KEY (run_id, table_name)
);

-- ---------------------------------------------------------------- indexes
-- Columns Power BI filters on: year_month, mode, district.

CREATE INDEX IF NOT EXISTS idx_route_perf_year_month   ON agg_route_performance (year_month);
CREATE INDEX IF NOT EXISTS idx_route_perf_mode         ON agg_route_performance (mode);
CREATE INDEX IF NOT EXISTS idx_route_perf_district     ON agg_route_performance (district);
CREATE INDEX IF NOT EXISTS idx_mode_summary_year_month ON agg_mode_summary (year_month);
CREATE INDEX IF NOT EXISTS idx_fare_mix_year_month     ON agg_fare_type_mix (year_month);
CREATE INDEX IF NOT EXISTS idx_stop_activity_district  ON agg_stop_activity (district);
CREATE INDEX IF NOT EXISTS idx_peak_analysis_mode      ON agg_peak_analysis (mode);
CREATE INDEX IF NOT EXISTS idx_transfer_mode           ON agg_transfer_behaviour (mode);
