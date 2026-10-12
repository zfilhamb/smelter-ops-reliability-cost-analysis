-- Create Schema ---------------
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;

-- Cleaning Table Daily Production ---------------------

-- 1a. Cek duplikat berdasarkan business key (record_id) sebelum dedup
SELECT record_id , COUNT(*)
FROM raw.daily_operations t
GROUP BY record_id
HAVING COUNT(*) > 1;

-- Bangun tabel final dengan seluruh perbaikan sekaligus
-- 1b. Dedup pakai ctid (row identity fisik) — simpan 1 baris per record_id
DROP TABLE IF EXISTS clean.daily_operations;
CREATE TABLE clean.daily_operations AS
WITH dedup AS (
    SELECT DISTINCT ON (record_id) *
    FROM raw.daily_operations t
    ORDER BY record_id, ctid
),
parse_date AS (
    SELECT
        *,
        CASE 
            WHEN date ~ '^\d{4}-\d{2}-\d{2}$'
                THEN TO_DATE(date, 'YYYY/MM/DD')
            WHEN date ~ '^\d{2}/\d{2}/\d{4}$'
                THEN TO_DATE(date, 'DD/MM/YYYY')
        ELSE NULL
    END AS date_clean
    FROM dedup
),
status_clean AS (
    SELECT 
        *,
        CASE lower(trim(operating_status))
            WHEN 'normal'               THEN 'Normal'
            WHEN 'reduce rate'          THEN 'Reduce Rate'
            WHEN 'shutdown'             THEN 'Shutdown'
            WHEN 'shut down'            THEN 'Shutdown'
            WHEN 'planned shut down'    THEN 'Planned Shutdown'
            WHEN 'planned shutdown'     THEN 'Planned Shutdown'
        ELSE initcap(trim(operating_status))
    END AS operating_status_clean
    FROM parse_date
),
value_fixes AS (
    SELECT *,
        -- Cu grade masuk akal di rentang 20-30%; kalau <5% kemungkinan salah taruh titik desimal (/10)
        CASE WHEN feed_cu_pct < 5  THEN feed_cu_pct * 10 ELSE feed_cu_pct END AS feed_cu_pct_fixed,
        -- Matte grade masuk akal 55-80%; kalau >200 kemungkinan salah taruh titik desimal (x10)
        CASE WHEN matte_grade_pct > 200 THEN matte_grade_pct / 10 ELSE matte_grade_pct END AS matte_grade_pct_fixed,
        -- Produksi tidak boleh negatif -> ambil nilai absolut (sign error input)
        CASE WHEN acid_production_t < 0 THEN ABS(acid_production_t) ELSE acid_production_t END AS acid_production_t_fixed,
        -- Energi harian wajar berkisar ratusan MWh; kalau >5000 kemungkinan kWh dimasukkan sebagai MWh (x1000)
        CASE WHEN energy_consumption_mwh > 5000 THEN energy_consumption_mwh / 1000 ELSE energy_consumption_mwh END AS energy_consumption_mwh_fixed,
        -- SO2 capture = 0 saat availability tinggi = kemungkinan sensor dropout, bukan capture nyata
        CASE WHEN so2_capture_pct = 0 AND furnace_availability_pct > 50 THEN NULL ELSE so2_capture_pct END AS so2_capture_pct_fixed,
        -- Feed di atas 1.4x kapasitas nominal (2.500 dmt/hari) dianggap double-entry
        CASE WHEN concentrate_feed_dmt > 3500 THEN concentrate_feed_dmt / 2 ELSE concentrate_feed_dmt END AS concentrate_feed_dmt_fixed
    FROM status_clean
),
imputed AS (
    -- Hitung median masing-masing variabel per bulan
    WITH monthly_median AS (
        SELECT
            DATE_TRUNC('month', date_clean) AS month,
            PERCENTILE_CONT(0.5)
                WITHIN GROUP (
                    ORDER BY feed_moisture_pct::double precision
                ) AS median_feed_moisture,
            PERCENTILE_CONT(0.5)
                WITHIN GROUP (
                    ORDER BY so2_capture_pct_fixed::double precision
                ) AS median_so2_capture,
            PERCENTILE_CONT(0.5)
                WITHIN GROUP (
                    ORDER BY energy_consumption_mwh_fixed::double precision
                ) AS median_energy
        FROM value_fixes
        GROUP BY DATE_TRUNC('month', date_clean)
    )
    SELECT
        v.*,
        COALESCE(
            v.feed_moisture_pct,
            m.median_feed_moisture
        ) AS feed_moisture_pct_imputed,
        COALESCE(
            v.so2_capture_pct_fixed,
            m.median_so2_capture
        ) AS so2_capture_pct_imputed,
        COALESCE(
            v.energy_consumption_mwh_fixed,
            m.median_energy
        ) AS energy_consumption_mwh_imputed
    FROM value_fixes v
    LEFT JOIN monthly_median m
        ON DATE_TRUNC('month', v.date_clean) = m.month
)
SELECT
    record_id,
    CAST(date_clean AS date) AS date,
    CAST(planned_feed_dmt AS DOUBLE PRECISION) AS planned_feed_dmt,
    CAST(concentrate_feed_dmt_fixed AS DOUBLE PRECISION) AS concentrate_feed_dmt,
    CAST(feed_cu_pct_fixed AS DOUBLE PRECISION) AS feed_cu_pct,
    CAST(feed_au_gpt AS DOUBLE PRECISION) AS feed_au_gpt,
    CAST(feed_sulfur_pct AS DOUBLE PRECISION) AS feed_sulfur_pct,
    CAST(feed_moisture_pct_imputed AS DOUBLE PRECISION) AS feed_moisture_pct,
    CAST(oxygen_enrichment_pct AS DOUBLE PRECISION) AS oxygen_enrichment_pct,
    CAST(matte_production_t AS DOUBLE PRECISION) AS matte_production_t,
    CAST(matte_grade_pct_fixed AS DOUBLE PRECISION) AS matte_grade_pct,
    CAST(slag_cu_pct AS DOUBLE PRECISION) AS slag_cu_pct,
    CAST(anode_production_t AS DOUBLE PRECISION) AS anode_production_t,
    CAST(cathode_production_t AS DOUBLE PRECISION) AS cathode_production_t,
    CAST(acid_production_t_fixed AS DOUBLE PRECISION) AS acid_production_t,
    CAST(so2_capture_pct_imputed AS DOUBLE PRECISION) AS so2_capture_pct,
    CAST(furnace_availability_pct AS DOUBLE PRECISION) AS furnace_availability_pct,
    CAST(energy_consumption_mwh_imputed AS DOUBLE PRECISION) AS energy_consumption_mwh,
    CAST(fuel_oil_kl AS DOUBLE PRECISION) AS fuel_oil_kl,
    operating_status_clean AS operating_status
FROM imputed;

SELECT *
FROM clean.daily_operations

-- Cleaning Table Downtime Events ---------------------

ALTER TABLE raw.downtime_events
ALTER COLUMN start_datetime TYPE timestamp
USING start_datetime::timestamp;

ALTER TABLE raw.downtime_events
ALTER COLUMN end_datetime TYPE timestamp
USING end_datetime::timestamp;

-- Bangun tabel final dengan seluruh perbaikan sekaligus
DROP TABLE IF EXISTS clean.downtime_events;
CREATE TABLE clean.downtime_events AS
-- Cleaning Equipment Coulumn
WITH equipment_clean AS (
    SELECT 
        *,
        CASE 
            WHEN lower(trim(equipment)) IN ('fsf', 'flash smelting furnace') THEN 'Flash Smelting Furnace'
            WHEN lower(trim(equipment)) IN ('dryer', 'concentrate dryer') THEN 'Concentrate Dryer'
            WHEN lower(trim(equipment)) IN ('o2 plant', 'oxygen plant') THEN 'Oxygen Plant'
            WHEN lower(trim(equipment)) = 'acid plant' THEN 'Acid Plant'
            ELSE initcap(trim(equipment))
        END AS equipment_fixed
    FROM raw.downtime_events
),
fixed_missing_value AS (
    SELECT
        *,
        COALESCE(
            NULLIF(TRIM(end_datetime), '')::timestamp,
            start_datetime + (ABS(duration_hr) * INTERVAL '1 hour')
            ) AS end_datetime_fixed,
        abs(duration_hr) AS duration_hr_fixed,
        COALESCE(NULLIF(TRIM(failure_category),''), 'Unclassified')AS failure_category_fixed
    FROM equipment_clean
)
SELECT
    event_id,
    equipment_fixed AS equipment,
    area,
    start_datetime,
    end_datetime_fixed AS end_datetime,
    duration_hr_fixed AS duration_hr,
    planned_duration_hr,
    failure_category_fixed AS failure_category,
    is_planned,
    impact_type,
    throughput_loss_pct,
    cause_description,
    repair_cost_usd
FROM fixed_missing_value;

SELECT *
FROM clean.downtime_events

-- Cleaning Table Cost Report ---------------------

DROP TABLE IF EXISTS clean.cost_report;
CREATE TABLE clean.cost_report AS 
WITH standardized AS (
    SELECT
        *,
        ctid AS source_ctid,
        CASE
            WHEN lower(trim(cost_center)) LIKE 'smelting%' THEN 'Smelting (FSF/FCF)'
            WHEN lower(trim(cost_center)) = 'acid plant' THEN 'Acid Plants'
            WHEN lower(trim(cost_center)) LIKE 'electro refinery' 
            OR lower(trim(cost_center)) = 'electrorefinery' THEN 'Electro Refinery'
            ELSE trim(cost_center)
        END AS cost_center_fixed
    FROM raw.cost_report
),
dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER( PARTITION BY period, cost_center_fixed, cost_element ORDER BY source_ctid) AS rn
    FROM standardized
),
actual_usd_clean AS (
    SELECT
        c.*,
        CASE
            WHEN c.actual_usd < 0 AND c.budget_usd > 0 THEN ABS(c.actual_usd)
            WHEN c.actual_usd > c.budget_usd * 100 AND m.usd_idr IS NOT NULL THEN c.actual_usd / m.usd_idr
            ELSE c.actual_usd
        END AS actual_usd_fixed,
        (c.period_status = 'Closed' AND c.actual_usd IS NULL) AS actualusd_missing
    FROM dedup c
    LEFT JOIN raw.market_reference m ON m.month = c.period 
)
SELECT
    period,
    period_status,
    cost_center_fixed AS cost_center,
    cost_element,
    cost_behavior,
    budget_version,
    budget_usd,
    actual_usd_fixed AS actual_usd,
    actualusd_missing AS is_missing_actual_flag,
    currency
FROM actual_usd_clean
WHERE rn = 1;

SELECT *
FROM clean.cost_report cr

-- Cleaning Table Concentrate Stock -----------------

DROP TABLE IF EXISTS clean.concentrate_stock;
CREATE TABLE clean.concentrate_stock AS
SELECT
    month,
    opening_stock_dmt,
    receipts_from_concentrator_dmt,
    smelter_feed_dmt,
    closing_stock_reported_dmt,                                                    -- nilai resmi, dipakai di dashboard
    ROUND(opening_stock_dmt + receipts_from_concentrator_dmt - smelter_feed_dmt) AS closing_stock_calculated_dmt,
    ROUND(closing_stock_reported_dmt
          - (opening_stock_dmt + receipts_from_concentrator_dmt - smelter_feed_dmt)) AS reconciliation_variance_dmt,
    CASE
        WHEN ABS(closing_stock_reported_dmt
                 - (opening_stock_dmt + receipts_from_concentrator_dmt - smelter_feed_dmt)) > 0.01 * smelter_feed_dmt
        THEN 'Needs investigation'
        ELSE 'Reconciled'
    END AS reconciliation_status                                                    -- flag untuk PPC/gudang, bukan auto-fix
FROM raw.concentrate_stock;

SELECT *
FROM clean.concentrate_stock cs

-- Cleaning Table Peer Benchmark ---------------------

DROP TABLE IF EXISTS clean.peer_benchmark;
CREATE TABLE clean.peer_benchmark AS
SELECT
    benchmark_year, smelter_id, smelter_name, region, technology, capacity_kdmt_per_year,
    availability_pct, cu_recovery_pct, energy_intensity_gj_per_t_cu, so2_capture_pct,
    acid_yield_t_per_t_cu, conversion_cost_usd_per_t_cu,
    NULLIF(labour_productivity_t_cu_per_fte, 'n/a')::numeric AS labour_productivity_t_cu_per_fte
FROM raw.peer_benchmark;

SELECT *
FROM clean.peer_benchmark;

-- Create Table Clean Market Market Reference -------------
DROP TABLE IF EXISTS clean.market_reference;
CREATE TABLE clean.market_reference AS SELECT * FROM raw.market_reference;

SELECT *
FROM clean.market_reference;

-- Create Table Clean Production Plan -------------
DROP TABLE IF EXISTS clean.production_plan;
CREATE TABLE clean.production_plan AS SELECT * FROM raw.production_plan;

SELECT *
FROM clean.production_plan;

-- Create Table Dim Month -------------
DROP TABLE IF EXISTS clean.dim_month;
CREATE TABLE clean.dim_month AS
SELECT
  d::date                          AS month_key,
  EXTRACT(YEAR FROM d)::int        AS year,
  EXTRACT(MONTH FROM d)::int       AS month_num,
  TO_CHAR(d, 'FMMonth')            AS month_name
FROM generate_series('2025-01-01'::date, '2027-12-01'::date, interval '1 month') AS d;

SELECT *
FROM clean.dim_month

-----------------------------------------
----------------- EDA -------------------
-- CREATE HELPER VIEW
DROP VIEW IF EXISTS clean.v_monthly_ops;
CREATE OR REPLACE VIEW clean.v_monthly_ops AS
SELECT
    to_char(date, 'YYYY-MM')                                   AS month,
    COUNT(*)                                                   AS days,
    SUM(concentrate_feed_dmt)                                  AS feed_dmt,
    SUM(concentrate_feed_dmt * feed_cu_pct)
        / NULLIF(SUM(concentrate_feed_dmt), 0)                 AS feed_cu_pct_w,      -- kadar Cu tertimbang feed
    SUM(matte_production_t)                                    AS matte_t,
    SUM(matte_production_t * matte_grade_pct / 100)            AS cu_in_matte_t,
    SUM(concentrate_feed_dmt * feed_cu_pct / 100)              AS cu_in_feed_t,
    SUM(anode_production_t)                                    AS anode_t,
    SUM(cathode_production_t)                                  AS cathode_t,
    SUM(acid_production_t)                                     AS acid_t,
    AVG(furnace_availability_pct)                              AS avg_availability_pct,
    SUM(furnace_availability_pct) / 100.0                      AS available_days,
    SUM(energy_consumption_mwh)                                AS energy_mwh,
    SUM(fuel_oil_kl)                                           AS fuel_oil_kl
FROM clean.daily_operations
GROUP BY 1;
 
select *
FROM clean.v_monthly_ops

-- Hanya baris cost yang punya actual (like-for-like): periode Closed & actual tidak NULL.
-- Baris dengan actual hilang TIDAK dianggap 0 — dikeluarkan dari perbandingan budget vs actual.
DROP VIEW IF EXISTS clean.v_cost_comparable;
CREATE OR REPLACE VIEW clean.v_cost_comparable AS
SELECT * FROM clean.cost_report
WHERE period_status = 'Closed' AND actual_usd IS NOT NULL;
 
 
/* ============================================================================
   A. OPERASIONAL PLANT & PPC
   ============================================================================ */
 
-- A1. Ringkasan produksi bulanan + Cu recovery ke matte
SELECT
    month,
    ROUND(feed_dmt)                                                             AS feed_dmt,
    ROUND(feed_cu_pct_w::NUMERIC , 2)                                           AS feed_cu_pct,
    ROUND(cathode_t)                                                            AS cathode_t,
    ROUND(acid_t)                                                               AS acid_t,
    ROUND(avg_availability_pct::numeric, 1)                                     AS avg_availability_pct,
    ROUND(100 * cu_in_matte_t::numeric / NULLIF(cu_in_feed_t::NUMERIC , 0), 2)  AS cu_recovery_to_matte_pct,
    ROUND(energy_mwh::NUMERIC / NULLIF(cathode_t::NUMERIC , 0), 3)              AS mwh_per_t_cathode
FROM clean.v_monthly_ops
ORDER BY month;
 
-- A2. PPC: Plan vs Actual bulanan (feed, cathode, acid) + variance kumulatif YTD
SELECT
    p.month,
    p.plan_version,
    p.plan_concentrate_feed_dmt                                AS plan_feed,
    ROUND(a.feed_dmt)                                          AS actual_feed,
    ROUND(a.feed_dmt - p.plan_concentrate_feed_dmt)            AS feed_var,
    ROUND(100 * (a.feed_dmt::NUMERIC / p.plan_concentrate_feed_dmt::NUMERIC - 1), 1) AS feed_var_pct,
    p.plan_cathode_t                                           AS plan_cathode,
    ROUND(a.cathode_t)                                         AS actual_cathode,
    ROUND(100 * (a.cathode_t::NUMERIC / p.plan_cathode_t::NUMERIC - 1), 1)       AS cathode_var_pct,
    ROUND(100 * (a.acid_t::NUMERIC / p.plan_acid_t::NUMERIC - 1), 1)             AS acid_var_pct,
    ROUND(SUM(a.cathode_t - p.plan_cathode_t)
          OVER (PARTITION BY LEFT(p.month, 4) ORDER BY p.month)) AS cathode_var_ytd
FROM clean.production_plan p
JOIN clean.v_monthly_ops a ON a.month = p.month
ORDER BY p.month;
 
 
-- A3. Penyebab variance feed: efek AVAILABILITY (hari efektif) vs efek RATE (laju feed per hari efektif)
--     availability_effect + rate_effect = actual_feed - plan_feed
WITH x AS (
    SELECT
        p.month,
        p.plan_concentrate_feed_dmt                                    AS plan_feed,
        a.feed_dmt                                                     AS actual_feed,
        (p.calendar_days - p.planned_shutdown_days)::numeric           AS plan_days,
        a.available_days                                               AS actual_days
    FROM clean.production_plan p
    JOIN clean.v_monthly_ops a ON a.month = p.month
)
SELECT
    month,
    ROUND(actual_feed - plan_feed)                                     AS total_var_dmt,
    ROUND((actual_days - plan_days) * (plan_feed / plan_days))         AS availability_effect_dmt,
    ROUND((actual_feed / actual_days - plan_feed / plan_days) * actual_days) AS rate_effect_dmt
FROM x
ORDER BY month;
 
 
-- A4a. Driver recovery: korelasi harian (hari operasi normal saja, availability > 90%)
SELECT
    ROUND(CORR(oxygen_enrichment_pct, matte_grade_pct)::numeric, 3)  AS corr_o2_vs_matte_grade,
    ROUND(CORR(oxygen_enrichment_pct, slag_cu_pct)::numeric, 3)      AS corr_o2_vs_slag_cu,
    ROUND(CORR(feed_cu_pct, slag_cu_pct)::numeric, 3)                AS corr_feedcu_vs_slag_cu,
    ROUND(CORR(feed_sulfur_pct, acid_production_t / NULLIF(concentrate_feed_dmt, 0))::numeric, 3) AS corr_sulfur_vs_acid_yield
FROM clean.daily_operations
WHERE furnace_availability_pct > 90;
 
-- A4b. Kuintil oxygen enrichment -> rata-rata matte grade & slag Cu loss
SELECT
    q AS o2_quintile,
    ROUND(MIN(oxygen_enrichment_pct::NUMERIC), 1) AS o2_min,
    ROUND(MAX(oxygen_enrichment_pct::NUMERIC), 1) AS o2_max,
    ROUND(AVG(matte_grade_pct::NUMERIC), 2)       AS avg_matte_grade,
    ROUND(AVG(slag_cu_pct::NUMERIC), 3)           AS avg_slag_cu,
    COUNT(*)                             AS days
FROM (
    SELECT *, NTILE(5) OVER (ORDER BY oxygen_enrichment_pct) AS q
    FROM clean.daily_operations
    WHERE furnace_availability_pct > 90 AND oxygen_enrichment_pct IS NOT NULL
) t
GROUP BY q
ORDER BY q;
 
 
-- A5. Distribusi hari operasi per status per bulan
SELECT
    to_char(date, 'YYYY-MM')                                    AS month,
    COUNT(*) FILTER (WHERE operating_status = 'Normal')          AS normal_days,
    COUNT(*) FILTER (WHERE operating_status = 'Reduced Rate')    AS reduced_days,
    COUNT(*) FILTER (WHERE operating_status = 'Shutdown')        AS shutdown_days,
    COUNT(*) FILTER (WHERE operating_status = 'Planned Shutdown') AS planned_shutdown_days
FROM clean.daily_operations
GROUP BY 1
ORDER BY 1;

/* ============================================================================
   B. DOWNTIME — bahan untuk production meeting & rekomendasi solusi
   ============================================================================ */
 
-- B1. Pareto downtime TIDAK terencana per equipment
--     lost_hr_equiv = durasi x % throughput loss (jam-setara kehilangan produksi penuh)
WITH e AS (
    SELECT
        equipment,
        COUNT(*)                                            AS events,
        SUM(duration_hr)                                    AS downtime_hr,
        SUM(duration_hr * throughput_loss_pct / 100.0)      AS lost_hr_equiv,
        SUM(repair_cost_usd)                                AS repair_cost_usd
    FROM clean.downtime_events
    WHERE is_planned = 'N' AND impact_type <> 'No Impact'
    GROUP BY equipment
)
SELECT
    equipment, events,
    ROUND(downtime_hr::NUMERIC, 1)                                   AS downtime_hr,
    ROUND(lost_hr_equiv::NUMERIC, 1)                                 AS lost_hr_equiv,
    ROUND(100 * lost_hr_equiv::NUMERIC / SUM(lost_hr_equiv::NUMERIC) OVER (), 1) AS share_pct,
    ROUND(100 * SUM(lost_hr_equiv::NUMERIC) OVER (ORDER BY lost_hr_equiv DESC)
              / SUM(lost_hr_equiv::NUMERIC) OVER (), 1)              AS cumulative_pct,
    repair_cost_usd
FROM e
ORDER BY lost_hr_equiv DESC;
 
 
-- B2. Pareto per kategori kegagalan (unplanned)
WITH c AS (
    SELECT failure_category,
           COUNT(*) AS events,
           SUM(duration_hr * throughput_loss_pct / 100.0) AS lost_hr_equiv,
           SUM(repair_cost_usd) AS repair_cost_usd
    FROM clean.downtime_events
    WHERE is_planned = 'N' AND impact_type <> 'No Impact'
    GROUP BY failure_category
)
SELECT failure_category, events, ROUND(lost_hr_equiv::NUMERIC, 1) AS lost_hr_equiv,
       ROUND(100 * lost_hr_equiv::NUMERIC / SUM(lost_hr_equiv::NUMERIC) OVER (), 1) AS share_pct,
       repair_cost_usd
FROM c
ORDER BY lost_hr_equiv DESC;
 
 
-- B3. MTBF / MTTR per equipment (basis jam kalender periode data; hanya kegagalan yang berdampak)
WITH period AS (SELECT COUNT(*) * 24.0 AS total_hr FROM clean.daily_operations),
f AS (
    SELECT equipment, COUNT(*) AS failures, SUM(duration_hr) AS down_hr
    FROM clean.downtime_events
    WHERE is_planned = 'N' AND impact_type <> 'No Impact'
    GROUP BY equipment
)
SELECT
    equipment, failures,
    ROUND(down_hr::NUMERIC, 1)                                  AS down_hr,
    ROUND(down_hr::NUMERIC / failures::NUMERIC, 1)                       AS mttr_hr,
    ROUND((total_hr - down_hr) / failures)             AS mtbf_hr,
    ROUND(100 * (total_hr - down_hr::NUMERIC) / total_hr::NUMERIC, 2)    AS equipment_availability_pct
FROM f CROSS JOIN period
ORDER BY mtbf_hr;                                      -- MTBF terendah = paling sering gagal
 
 
-- B4a. Overrun event terencana (turnaround): durasi rencana vs aktual + estimasi dampak produksi
--      Estimasi sederhana: jam overrun x laju feed hari Normal x cathode per dmt feed x harga LME bulan tsb.
--      est_lost_value_usd = NILAI KOTOR penjualan yang tertunda (bukan margin) — sebutkan asumsi ini saat presentasi.
WITH base AS (
    SELECT AVG(concentrate_feed_dmt)                                AS normal_feed_per_day,
           SUM(cathode_production_t) / NULLIF(SUM(concentrate_feed_dmt), 0) AS cathode_per_dmt
    FROM clean.daily_operations WHERE operating_status = 'Normal'
)
SELECT
    d.event_id, d.equipment, d.start_datetime,
    d.planned_duration_hr, d.duration_hr,
    d.duration_hr - d.planned_duration_hr                                   AS overrun_hr,
    ROUND(100 * (d.duration_hr::NUMERIC / d.planned_duration_hr::NUMERIC - 1), 1)             AS overrun_pct,
    ROUND((d.duration_hr - d.planned_duration_hr) / 24 * b.normal_feed_per_day)      AS est_lost_feed_dmt,
    ROUND((d.duration_hr - d.planned_duration_hr) / 24 * b.normal_feed_per_day * b.cathode_per_dmt) AS est_lost_cathode_t,
    ROUND((d.duration_hr - d.planned_duration_hr) / 24 * b.normal_feed_per_day * b.cathode_per_dmt
          * m.lme_copper_usd_per_t)                                         AS est_lost_value_usd
FROM clean.downtime_events d
CROSS JOIN base b
JOIN clean.market_reference m ON m.month = to_char(d.start_datetime, 'YYYY-MM')
WHERE d.is_planned = 'Y' AND d.planned_duration_hr IS NOT NULL
  AND d.duration_hr > d.planned_duration_hr;
 
 
-- B4b. Dampak biaya bulan turnaround (Okt 2025) per cost element — budget vs actual like-for-like
SELECT
    cost_element,
    ROUND(SUM(budget_usd))                                       AS budget_usd,
    ROUND(SUM(actual_usd))                                       AS actual_usd,
    ROUND(SUM(actual_usd - budget_usd))                          AS variance_usd,
    ROUND(100 * (SUM(actual_usd::NUMERIC) / SUM(budget_usd::NUMERIC) - 1), 1)      AS variance_pct
FROM clean.v_cost_comparable
WHERE period = '2025-10'
GROUP BY cost_element
ORDER BY variance_usd DESC;
 
 
-- B5. Tren downtime tidak terencana per bulan
SELECT
    to_char(start_datetime, 'YYYY-MM')                           AS month,
    COUNT(*)                                                     AS events,
    ROUND(SUM(duration_hr::NUMERIC), 1)                                   AS downtime_hr,
    ROUND(SUM(duration_hr::NUMERIC * throughput_loss_pct::NUMERIC / 100.0), 1)     AS lost_hr_equiv,
    ROUND(SUM(repair_cost_usd))                                  AS repair_cost_usd
FROM clean.downtime_events
WHERE is_planned = 'N' AND impact_type <> 'No Impact'
GROUP BY 1
ORDER BY 1;

/* ============================================================================
   C. COST REPORT, BUDGET & BUSINESS PRESENTATION
   ============================================================================ */
 
-- C1. Budget vs Actual bulanan (like-for-like) + jumlah baris actual yang hilang
SELECT
    c.period,
    ROUND(SUM(c.budget_usd))                                     AS budget_usd,
    ROUND(SUM(c.actual_usd))                                     AS actual_usd,
    ROUND(SUM(c.actual_usd - c.budget_usd))                      AS variance_usd,
    ROUND(100 * (SUM(c.actual_usd::NUMERIC) / SUM(c.budget_usd::NUMERIC) - 1), 1)  AS variance_pct,
    (SELECT COUNT(*) FROM clean.cost_report x
      WHERE x.period = c.period AND x.is_missing_actual_flag)    AS missing_actual_rows
FROM clean.v_cost_comparable c
GROUP BY c.period
ORDER BY c.period;
 
 
-- C2. Budget vs Actual per cost element per tahun
SELECT
    LEFT(period, 4)                                              AS year,
    cost_element,
    cost_behavior,
    ROUND(SUM(budget_usd))                                       AS budget_usd,
    ROUND(SUM(actual_usd))                                       AS actual_usd,
    ROUND(100 * (SUM(actual_usd::NUMERIC) / SUM(budget_usd::NUMERIC) - 1), 1)      AS variance_pct
FROM clean.v_cost_comparable
GROUP BY 1, 2, 3
ORDER BY 1, SUM(actual_usd - budget_usd) DESC;
 
 
-- C3. Cost per ton cathode: budget (plan cathode) vs actual (produksi aktual).
--     Bulan dengan missing_actual_rows > 0 -> actual UNDERSTATED, jangan ditampilkan sebagai angka final.
WITH c AS (
    SELECT period,
           SUM(actual_usd)                                        AS actual_usd,
           SUM(budget_usd)                                        AS budget_usd,
           COUNT(*) FILTER (WHERE is_missing_actual_flag)         AS missing_rows
    FROM clean.cost_report
    WHERE period_status = 'Closed'
    GROUP BY period
)
SELECT
    c.period,
    ROUND(c.budget_usd / p.plan_cathode_t)                       AS budget_usd_per_t,
    ROUND(c.actual_usd / a.cathode_t)                            AS actual_usd_per_t,
    ROUND(100 * ((c.actual_usd::NUMERIC / a.cathode_t::NUMERIC) / (c.budget_usd::NUMERIC / p.plan_cathode_t::NUMERIC) - 1), 1) AS variance_pct,
    c.missing_rows
FROM c
JOIN clean.production_plan p ON p.month = c.period
JOIN clean.v_monthly_ops   a ON a.month = c.period
ORDER BY c.period;
 
 
-- C4. Ranking cost center berdasarkan overrun (semua periode Closed, like-for-like)
SELECT
    cost_center,
    ROUND(SUM(budget_usd))                                       AS budget_usd,
    ROUND(SUM(actual_usd))                                       AS actual_usd,
    ROUND(SUM(actual_usd - budget_usd))                          AS variance_usd,
    ROUND(100 * (SUM(actual_usd::NUMERIC) / SUM(budget_usd::NUMERIC) - 1), 1)      AS variance_pct,
    RANK() OVER (ORDER BY SUM(actual_usd - budget_usd) DESC)     AS overrun_rank
FROM clean.v_cost_comparable
GROUP BY cost_center
ORDER BY overrun_rank;
 
 
-- C5. Listrik: pisahkan variance PRICE vs USAGE (tarif budget diturunkan dari budget cost / plan MWh)
--     usage_var + price_var = (actual MWh x actual tarif) - budget listrik
WITH bud AS (
    SELECT period, SUM(budget_usd) AS budget_usd
    FROM clean.cost_report WHERE cost_element = 'Electricity' GROUP BY period
)
SELECT
    o.month,
    ROUND(p.plan_energy_mwh)                                     AS plan_mwh,
    ROUND(o.energy_mwh)                                          AS actual_mwh,
    ROUND(b.budget_usd::NUMERIC / p.plan_energy_mwh::NUMERIC, 2)                   AS budget_tariff,
    m.electricity_tariff_usd_per_mwh                             AS actual_tariff,
    ROUND((o.energy_mwh - p.plan_energy_mwh) * (b.budget_usd / p.plan_energy_mwh)) AS usage_var_usd,
    ROUND((m.electricity_tariff_usd_per_mwh - b.budget_usd / p.plan_energy_mwh) * o.energy_mwh) AS price_var_usd
FROM clean.v_monthly_ops o
JOIN clean.production_plan  p ON p.month = o.month
JOIN bud                    b ON b.period = o.month
JOIN clean.market_reference m ON m.month = o.month
ORDER BY o.month;
 
 
-- C6. Struktur biaya: porsi Fixed / Semi-variable / Variable (dasar untuk budgeting & sensitivitas volume)
SELECT
    LEFT(period, 4)                                              AS year,
    cost_behavior,
    ROUND(SUM(actual_usd))                                       AS actual_usd,
    ROUND(100 * SUM(actual_usd::NUMERIC) / SUM(SUM(actual_usd::NUMERIC)) OVER (PARTITION BY LEFT(period, 4)), 1) AS share_pct
FROM clean.v_cost_comparable
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

/* ============================================================================
   D. BENCHMARKING vs PEER SMELTER
   ============================================================================ */
 
-- D1. Posisi OWN-PLANT vs peer (2025): rank, median peer, selisih, dan gap ke kuartil teratas
--     Diurutkan dari gap terbesar -> kandidat "areas of improvement" paling prioritas.
--     Ganti benchmark_year = 2024 untuk membandingkan tahun lain.
WITH long AS (
    SELECT b.benchmark_year, b.smelter_id, k.kpi, k.val::numeric AS val, k.higher_is_better
    FROM clean.peer_benchmark b
    CROSS JOIN LATERAL (VALUES
        ('availability_pct',                b.availability_pct,                true),
        ('cu_recovery_pct',                 b.cu_recovery_pct,                 true),
        ('so2_capture_pct',                 b.so2_capture_pct,                 true),
        ('acid_yield_t_per_t_cu',           b.acid_yield_t_per_t_cu,           true),
        ('labour_productivity_t_cu_per_fte', b.labour_productivity_t_cu_per_fte, true),
        ('energy_intensity_gj_per_t_cu',    b.energy_intensity_gj_per_t_cu,    false),
        ('conversion_cost_usd_per_t_cu',    b.conversion_cost_usd_per_t_cu,    false)
    ) AS k(kpi, val, higher_is_better)
    WHERE k.val IS NOT NULL
),
ranked AS (
    SELECT *,
        RANK()  OVER (PARTITION BY benchmark_year, kpi
                      ORDER BY CASE WHEN higher_is_better THEN -val ELSE val END) AS rnk,
        COUNT(*) OVER (PARTITION BY benchmark_year, kpi)                          AS n_smelters
    FROM long
),
peer AS (
    SELECT benchmark_year, kpi,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val) AS peer_median,
        -- kuartil teratas: Q3 untuk KPI "makin tinggi makin baik", Q1 untuk "makin rendah makin baik"
        PERCENTILE_CONT(CASE WHEN higher_is_better THEN 0.75 ELSE 0.25 END)
            WITHIN GROUP (ORDER BY val) AS peer_top_quartile
    FROM long
    WHERE smelter_id <> 'OWN-PLANT'
    GROUP BY benchmark_year, kpi, higher_is_better
)
SELECT
    r.kpi,
    ROUND(r.val, 2)                                   AS own_value,
    ROUND(p.peer_median::numeric, 2)                  AS peer_median,
    ROUND(p.peer_top_quartile::numeric, 2)            AS peer_top_quartile,
    r.rnk || ' / ' || r.n_smelters                    AS rank_of_n,
    CASE WHEN r.higher_is_better
         THEN ROUND(100 * (p.peer_top_quartile::numeric - r.val) / p.peer_top_quartile::numeric, 1)
         ELSE ROUND(100 * (r.val - p.peer_top_quartile::numeric) / p.peer_top_quartile::numeric, 1)
    END                                               AS gap_to_top_quartile_pct   -- positif = tertinggal dari kuartil teratas
FROM ranked r
JOIN peer p ON p.benchmark_year = r.benchmark_year AND p.kpi = r.kpi
WHERE r.smelter_id = 'OWN-PLANT' AND r.benchmark_year = 2025
ORDER BY gap_to_top_quartile_pct DESC;
 
 
-- D2. Perubahan 2024 -> 2025: OWN-PLANT vs median peer (apakah kita mengejar atau tertinggal?)
WITH long AS (
    SELECT b.benchmark_year, b.smelter_id, k.kpi, k.val::numeric AS val
    FROM clean.peer_benchmark b
    CROSS JOIN LATERAL (VALUES
        ('availability_pct',             b.availability_pct),
        ('cu_recovery_pct',              b.cu_recovery_pct),
        ('energy_intensity_gj_per_t_cu', b.energy_intensity_gj_per_t_cu),
        ('conversion_cost_usd_per_t_cu', b.conversion_cost_usd_per_t_cu)
    ) AS k(kpi, val)
    WHERE k.val IS NOT NULL
)
SELECT
    kpi,
    ROUND(100 * (MAX(val) FILTER (WHERE smelter_id = 'OWN-PLANT' AND benchmark_year = 2025)
               / MAX(val) FILTER (WHERE smelter_id = 'OWN-PLANT' AND benchmark_year = 2024) - 1)::numeric, 2) AS own_change_pct,
    ROUND(100 * (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val) FILTER (WHERE smelter_id <> 'OWN-PLANT' AND benchmark_year = 2025)
               / PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val) FILTER (WHERE smelter_id <> 'OWN-PLANT' AND benchmark_year = 2024) - 1)::numeric, 2) AS peer_median_change_pct
FROM long
GROUP BY kpi
ORDER BY kpi;
 
 
/* ============================================================================
   E. KOORDINASI PLANNING: STOK KONSENTRAT, GRADE & FORECAST
   ============================================================================ */
 
-- E1. Hari cadangan stok konsentrat (stock coverage) per bulan + status rekonsiliasi
--     Coverage dihitung dengan laju feed per HARI EFEKTIF (bukan rata-rata kalender), supaya bulan
--     shutdown/turnaround tidak terlihat seolah stoknya "melimpah".
SELECT
    s.month,
    ROUND(s.closing_stock_reported_dmt)                                   AS closing_stock_dmt,
    ROUND(s.closing_stock_reported_dmt::NUMERIC / (o.feed_dmt::NUMERIC / o.available_days::NUMERIC), 1) AS coverage_days_at_run_rate,
    s.reconciliation_variance_dmt,
    s.reconciliation_status
FROM clean.concentrate_stock s
JOIN clean.v_monthly_ops o ON o.month = s.month
ORDER BY s.month;
 
 
-- E2. Kadar Cu feed: plan vs actual + dampak ke Cu masuk (ton Cu) — dasar re-forecast plan
SELECT
    p.month,
    p.plan_feed_cu_pct,
    ROUND(o.feed_cu_pct_w::NUMERIC, 2)                                        AS actual_feed_cu_pct,
    ROUND(o.feed_cu_pct_w::NUMERIC - p.plan_feed_cu_pct::NUMERIC, 2)                   AS grade_gap_pct_pt,
    ROUND((o.feed_cu_pct_w - p.plan_feed_cu_pct) / 100 * o.feed_dmt) AS cu_units_impact_t
FROM clean.production_plan p
JOIN clean.v_monthly_ops o ON o.month = p.month
ORDER BY p.month;
 
 
-- E3. Baseline run-rate Sep-Des 2026: proyeksi dari 180 hari terakhir vs plan (Re-forecast Jul-2026)
--     Asumsi sederhana: laju feed & cathode per dmt = rata-rata 180 hari terakhir (sudah mencakup availability losses).
WITH rr AS (
    SELECT
        AVG(concentrate_feed_dmt)                                         AS avg_daily_feed,
        SUM(cathode_production_t) / NULLIF(SUM(concentrate_feed_dmt), 0)  AS cathode_per_dmt
    FROM clean.daily_operations
    WHERE date > (SELECT MAX(date) FROM clean.daily_operations) - 180
)
SELECT
    p.month,
    p.plan_version,
    p.plan_concentrate_feed_dmt                                           AS plan_feed,
    ROUND(rr.avg_daily_feed * (p.calendar_days - p.planned_shutdown_days)) AS runrate_feed,
    ROUND(rr.avg_daily_feed * (p.calendar_days - p.planned_shutdown_days) - p.plan_concentrate_feed_dmt) AS feed_gap_dmt,
    p.plan_cathode_t                                                      AS plan_cathode,
    ROUND(rr.avg_daily_feed * (p.calendar_days - p.planned_shutdown_days) * rr.cathode_per_dmt) AS runrate_cathode
FROM clean.production_plan p
CROSS JOIN rr
WHERE p.month BETWEEN '2026-09' AND '2026-12'
ORDER BY p.month;
 
 
/* ============================================================================
   F. DATA QUALITY TESTING (pasca-cleaning) — semua hasil idealnya 0 / kosong
   ============================================================================ */
 
-- F1. Kelengkapan kolom kunci (NULL pada oxygen/matte/slag di hari shutdown itu wajar, bukan error)
SELECT
    COUNT(*) FILTER (WHERE date IS NULL)                                                   AS null_date,
    COUNT(*) FILTER (WHERE concentrate_feed_dmt IS NULL)                                   AS null_feed,
    COUNT(*) FILTER (WHERE feed_cu_pct IS NULL)                                            AS null_cu,
    COUNT(*) FILTER (WHERE energy_consumption_mwh IS NULL)                                 AS null_energy,
    COUNT(*) FILTER (WHERE so2_capture_pct IS NULL AND furnace_availability_pct > 50)      AS null_so2_on_running_days,
    COUNT(*) FILTER (WHERE oxygen_enrichment_pct IS NULL AND furnace_availability_pct > 50) AS null_o2_on_running_days
FROM clean.daily_operations;
 
-- F2. Kontinuitas tanggal: tanggal yang hilang di antara min dan max (harus kosong)
SELECT d::date AS missing_date
FROM generate_series((SELECT MIN(date) FROM clean.daily_operations),
                     (SELECT MAX(date) FROM clean.daily_operations), interval '1 day') d
LEFT JOIN clean.daily_operations o ON o.date = d::date
WHERE o.date IS NULL;
 
-- F3. Logika proses: pelanggaran aturan bisnis sederhana
SELECT
    COUNT(*) FILTER (WHERE cathode_production_t > anode_production_t)                      AS cathode_gt_anode,
    COUNT(*) FILTER (WHERE concentrate_feed_dmt > 2500)                                    AS feed_above_nominal,
    COUNT(*) FILTER (WHERE furnace_availability_pct = 0 AND concentrate_feed_dmt > 0)      AS feed_while_down,
    COUNT(*) FILTER (WHERE furnace_availability_pct > 90 AND concentrate_feed_dmt < 1500)  AS low_feed_while_up,
    COUNT(*) FILTER (WHERE feed_cu_pct NOT BETWEEN 15 AND 35)                              AS cu_out_of_range,
    COUNT(*) FILTER (WHERE matte_grade_pct NOT BETWEEN 55 AND 80)                          AS matte_out_of_range
FROM clean.daily_operations;
 
-- F4. Cross-table check: feed bulanan di daily_operations vs smelter_feed di concentrate_stock (selisih > 0,5% = curiga)
SELECT
    o.month,
    ROUND(o.feed_dmt)                                          AS feed_daily_ops,
    s.smelter_feed_dmt                                         AS feed_stock_table,
    ROUND(100 * (o.feed_dmt::NUMERIC - s.smelter_feed_dmt::NUMERIC) / s.smelter_feed_dmt::NUMERIC, 2) AS diff_pct
FROM clean.v_monthly_ops o
JOIN clean.concentrate_stock s ON s.month = o.month
WHERE ABS(o.feed_dmt - s.smelter_feed_dmt) / s.smelter_feed_dmt > 0.005;
 
-- F5. Duplikat business key pada tabel clean (semua harus kosong)
SELECT 'daily_operations' AS tbl, record_id::text AS k, COUNT(*) FROM clean.daily_operations GROUP BY record_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'downtime_events', event_id, COUNT(*) FROM clean.downtime_events GROUP BY event_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'cost_report', period || '|' || cost_center || '|' || cost_element, COUNT(*)
FROM clean.cost_report GROUP BY period, cost_center, cost_element HAVING COUNT(*) > 1;
 
-- F6. Sisa outlier biaya: rasio actual/budget per cost element (nilai ekstrem = koreksi belum tuntas)
SELECT
    cost_element,
    ROUND(MIN(actual_usd::NUMERIC / NULLIF(budget_usd::NUMERIC, 0)), 2) AS min_ratio,
    ROUND(AVG(actual_usd::NUMERIC / NULLIF(budget_usd::NUMERIC, 0)), 2) AS avg_ratio,
    ROUND(MAX(actual_usd::NUMERIC / NULLIF(budget_usd::NUMERIC, 0)), 2) AS max_ratio
FROM clean.v_cost_comparable
WHERE budget_usd > 0
GROUP BY cost_element
ORDER BY max_ratio DESC;