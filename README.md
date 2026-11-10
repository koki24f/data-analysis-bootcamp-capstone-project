# CityTransit — Public Transport Ridership Analytics

Capstone project for the Data Analysis Bootcamp. Four raw exports from the CityTransit fare system (ticket validations, routes, vehicles, stops) are profiled, cleaned, joined and aggregated in Jupyter notebooks. The results are nine clean tables that feed a three-page Power BI report and an SQLite warehouse.

---

## Project structure

```
├── data/
│   ├── raw/                     # the four original CSV exports (input, never modified)
│   ├── interim/                 # parquet files passed between notebooks
│   ├── processed/               # nine aggregate CSVs + _manifest.csv (Power BI input)
│   ├── rejects/                 # rejected_validations.csv: every dropped row + reject_reason
│   └── warehouse.db             # SQLite warehouse (bonus)
├── notebooks/
│   ├── 01_ingest_and_profile.ipynb
│   ├── 02_clean.ipynb
│   ├── 03_join_and_explore.ipynb
│   ├── 04_aggregate_and_export.ipynb
│   └── 05_database_bonus.ipynb
├── sql/schema.sql               # explicit DDL for the warehouse (bonus)
├── data_generator/              # instructor's synthetic data generator (not part of the pipeline)
├── docs/assignment_brief.md
├── report.pbix                  # Power BI report
├── requirements.txt
└── README.md
```

## How to run

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate     macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
jupyter notebook
```

Open the `notebooks/` folder and run the notebooks **in order, 01 → 05**, each with *Kernel → Restart & Run All*. Each notebook reads only what the previous one saved, so any notebook can be rerun on its own as long as the earlier ones have run once.

| # | Notebook | Reads | Writes |
|---|---|---|---|
| 01 | Ingest & profile | `data/raw/*.csv` | `data/interim/*_raw.parquet` |
| 02 | Clean | `*_raw.parquet` | `*_clean.parquet`, `data/rejects/rejected_validations.csv` |
| 03 | Join & explore | `*_clean.parquet` | `data/interim/fact_validations.parquet` |
| 04 | Aggregate & export | `fact_validations.parquet` | `data/processed/*.csv`, `_manifest.csv` |
| 05 | Database (bonus) | `data/processed/*.csv`, `sql/schema.sql` | `data/warehouse.db` |

Paths are relative to the project root, so the notebooks work on any computer. Interim files are stored as Parquet because it keeps the data types (string IDs, nullable integers, booleans, timestamps) between notebooks; CSV would turn them back into text.

---

## Cleaning decisions

Row flow for validations: **81,600 raw → 79,149 clean (2,451 rejected)**. Every rejected row is saved in `data/rejects/rejected_validations.csv` with its `reject_reason`, and Notebook 02 asserts that raw − rejected = clean.

| Reject reason | Rows |
|---|---:|
| Exact duplicate row | 802 |
| Duplicate `validation_id` (kept first) | 798 |
| Missing `passenger_count` | 811 |
| Unknown `route_id` / `vehicle_id` / `stop_id` | 40 |
| Unparseable `validation_ts` | 0 |

### Validations

| Column | Decision | Why |
|---|---|---|
| duplicates | Drop exact copies first, then repeated `validation_id`, keeping the first occurrence. | One validation = one boarding; duplicates would double-count passengers and revenue. Dropping exact copies first means every removed row is counted once. |
| `validation_ts` | Parse the three formats separately with explicit patterns: `%Y-%m-%d %H:%M:%S`, `%d/%m/%Y %H:%M`, `%B %d, %Y %I:%M %p`. | The slash format is **day/month** (the first number goes up to 31, the second only to 6). A generic parser (`format="mixed"`) reads `06/03/2024` as 3 June, which misdated 5,566 rows and created fake ridership in July–December. |
| ID columns | Strip whitespace. | About 15% of `route_id` values had a trailing space and would not join to the routes table. |
| `fare_type` | Lower-case, strip, then map 17 spellings to `Adult`, `Student`, `Senior`, `Child`, `Pass Holder`. An assertion stops the notebook if an unknown spelling appears. | `Full Fare` = Adult, `Senior Citizen` = Senior, `Kid` = Child, `PassHolder`/`Monthly Pass` = Pass Holder. |
| `transfer_flag` | `Y`/`1`/`TRUE` → `True`, `N`/`0`/`FALSE` → `False` (nullable boolean). | Six spellings of two values. Read as text in Notebook 01 so that `TRUE`/`FALSE` are not converted too early. |
| `passenger_count` | Null → drop and log. Negative → keep, flag `is_reversed = True`. | Without a count the boarding cannot be measured. Negatives are reversed validations; keeping them makes totals *net* boardings (a reversal cancels its original boarding). |
| `fare_amount` | Null → median of the same `fare_type`. Above the 99.5th percentile → capped at that percentile, **calculated per fare type**. | Fares depend on ticket type (Adult ≈ 2.50, Pass Holder ≈ 0), so one overall median or cap would be wrong for most rows. The median ignores the 25 absurd values (1,234–9,999). Capping keeps the boarding, which is valid even when the fare field is corrupt. |
| `card_id` | Blank → `SINGLE_RIDE`. | Paper tickets have no card. They are valid boardings and are kept, but they are left out of `unique_cards`. |

### Master tables

| Table | Decision |
|---|---|
| routes | `route_name` trimmed + title case; `mode` trimmed + title case (10 spellings → Bus/Tram/Metro); null `district` → `Unknown`; null `route_length_km` → median of the same mode. |
| vehicles | `year_manufactured` outside 1980–2026 → null (15 vehicles: 1899 and 2035); `vehicle_age_band` from reference year 2026: `0-5`, `6-10`, `11-20`, `20+`, `Unknown`; null `capacity` → median of the same `vehicle_type`. |
| stops | `stop_name` trimmed + title case; `has_shelter` (`Y`/`N`/`1`/`0`) → boolean. |

### Referential integrity

Validations whose `route_id`, `vehicle_id` or `stop_id` is not in the cleaned master tables are rejected (`R999`, `V9999`, `S9999`: 40 rows). `card_id` is not checked, so `SINGLE_RIDE` validations are kept.

### Derived columns

`date`, `year`, `month`, `year_month` (YYYY-MM), `quarter`, `hour`, `day_of_week`, `is_weekend`, `time_period` (`Night (00-03)`, `Early (04-06)`, `AM Peak (07-09)`, `Midday (10-15)`, `PM Peak (16-18)`, `Evening (19-23)`) and `revenue = fare_amount × passenger_count`.

---

## Joining and load factor

- Validations → routes → vehicles → stops with `left` joins and `validate="many_to_one"`. The notebook asserts that the fact table has exactly 79,149 rows (no fan-out) and that every key found a match.
- The route district and the stop district are kept as two clearly named columns: `route_district` and `stop_district`.
- **Load factor** is calculated per **trip**, defined as one vehicle on one route on one date in one clock hour: `trip boardings / vehicle capacity`. All load-factor averages in the aggregate tables are averages over trips, not over validation rows.

## Aggregate tables (`data/processed/`)

| Table | Grain | Rows |
|---|---|---:|
| `agg_ridership_by_month` | year_month | 6 |
| `agg_ridership_by_hour` | hour, day_type | 48 |
| `agg_route_performance` | route_id, year_month | 360 |
| `agg_mode_summary` | mode, year_month | 18 |
| `agg_fare_type_mix` | fare_type, year_month | 30 |
| `agg_stop_activity` | stop_id | 400 |
| `agg_vehicle_utilisation` | vehicle_id | 180 |
| `agg_peak_analysis` | time_period, mode | 18 |
| `agg_transfer_behaviour` | year_month, mode | 18 |

All use named aggregations. Window operations (`transform`) produce `pct_of_daily_total`, `pct_of_monthly_boardings`, `pct_of_mode_total` and month-over-month growth (`boardings_mom_growth` in the monthly and mode tables). Money is rounded to 2 decimals, rates to 4. Before each file is written the notebook asserts that key columns have no nulls and that the grain is unique. `_manifest.csv` lists every file with row count, column count and generation time.

The columns required by the brief come first in each file. Helper columns are added at the end: `month_start` (an ISO date for Power BI), `route_length_km`, `capacity`, `period_order` (to sort time periods in the order of the day) and `validations`. The stop and vehicle tables start from the master tables, so a stop or vehicle with no boardings would still appear, with 0.

## Database (bonus, option A: SQLite)

`sql/schema.sql` defines all tables explicitly, with types, primary keys, `NOT NULL` and `CHECK` constraints, and indexes on `year_month`, `mode` and `district`. Notebook 05 loads each table with truncate-and-reload inside a transaction, rolling back on error, and logs every run in `pipeline_runs` and `pipeline_run_tables`. It then verifies row counts and measure totals against the CSVs. The notebook also shows that a second run does not duplicate rows and that a failing load is rolled back.

---

## Assumptions

- The data covers 1 January – 30 June 2024 (182 days: 130 weekdays, 52 weekend days).
- Timestamps in the `DD/MM/YYYY` format are day-first, confirmed by the data itself.
- A negative `passenger_count` is a reversal of an earlier boarding, so boardings and revenue are reported net.
- Pass Holder fares near 0 are correct: pass holders pay for the pass separately, so per-ride revenue understates their value.
- "Boardings" means the sum of `passenger_count`, not the number of validation rows.
- Vehicle age is calculated from 2026.

## Known limitations

- **Load factor is not a real occupancy measure.** On average a trip has only 1.01 validations, so the load factor mostly reflects vehicle size (≈ 1 / capacity). It is useful for comparing vehicle types and modes, not for saying how full a vehicle was. A real occupancy figure would need automatic passenger counts or trip-level schedules.
- Validations record boardings only, not alightings, so loads along a route cannot be reconstructed.
- `route_id` + `vehicle_id` + date + hour is an approximation of a trip; the data has no trip or timetable ID.
- Pass Holder revenue excludes the price of the pass itself.
- The tables at hour, time-period, stop and vehicle grain have no month column, so the report's month slicer cannot filter them.
- The data is synthetic (see `data_generator/`), which explains how evenly demand is spread over routes, stops and days.

---

## Summary of findings

Headline numbers (Jan–Jun 2024): **85,247 boardings**, **156,490 in fare revenue** (currency units as in the source data), **23,460 unique cards** (plus 9,441 single-ride paper tickets), average trip load factor **0.0097**.

1. **Ridership is stable.** Monthly boardings range from 13,600 to 14,700. The month-to-month changes (−7% to +7%) are explained by the number of days in each month: average daily boardings stay between 464 and 473. There is no growth or decline trend.
2. **Two strong peaks.** 08:00 and 17:00–18:00 each carry about 12% of the day's boardings. The AM and PM peak periods (6 hours in total) carry 61% of all boardings, for every mode.
3. **Weekends look like weekdays.** Average daily boardings are 460–475 on every day of the week, and the weekend hourly curve has the same commuter peaks. This is unusual and should be checked before any weekend service cuts.
4. **No route is clearly overloaded.** The busiest route (Thomas Dam Line, 1,506 boardings) carries only 12% more than the quietest (1,340). Boardings per stop are 209–218 in every district and 212–216 in every zone. District and mode totals mainly reflect how many stops or routes each has.
5. **Metro capacity is the least used.** Bus, tram and metro each carry about 1,400 boardings per route. A metro set holds about 620 people against about 70 on a standard bus, so the metro's trip load factor (0.002) is about one seventh of the bus figure (0.014). 21 metro sets serve 6 routes, and each set carries no more passengers than a standard bus.
6. **Trams are the hardest-working vehicles.** Each tram carries about 755 boardings, against about 400 for every other vehicle type, and is active on 178 of 182 days. The least-used vehicles are standard and articulated buses with about 340–360 boardings.
7. **Adults pay for the network.** Adult tickets are 56% of boardings but 76% of fare revenue. Pass Holders are 10% of boardings and 0.3% of per-ride revenue. The fare mix and the transfer rate (35–39% of validations) are stable across months and modes.

### Recommendations

- Match capacity to the two peaks; review midday and evening frequency (about one third of peak demand).
- Review metro capacity (shorter train sets or lower off-peak frequency) and check whether some of the 21 metro sets could be released.
- Check tram fleet reserves: trams are the most intensively used vehicles.
- Before cutting weekend service, confirm with the agency that weekend validations are complete, because weekday and weekend demand look identical.
- To answer "which routes are overloaded" with confidence, add automatic passenger counts or trip IDs to the data.

### Power BI report

`report.pbix` has three pages: Network Overview; Time & Demand Patterns; and Routes, Stops & Fleet. A synced month slicer filters all pages, and each page has a written insight. After changes to `data/processed/`, refresh the report with *Home → Refresh*.
