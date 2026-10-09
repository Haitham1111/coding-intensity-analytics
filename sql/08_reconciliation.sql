-- 08_reconciliation.sql
-- Question: Do the loaded numbers tie back to the staged CSV counts taken at pull time?
--  A. Staging rows = typed rows (nothing lost in the cast)
--  B. Rows/services loaded vs source_totals.csv (geo, AZ provider); 99201 rows dropped at pull time
--  C. Geography: National row services vs sum of State rows, per year
--  D. Arizona: provider-file services vs geography-file Arizona services (2019, 2024)
-- Gaps in C/D are expected: files are built and suppressed differently (CMS hides cells with <= 10 beneficiaries).
USE Coding_Intensity;
SET NOCOUNT ON;

-- A. staging vs typed
SELECT 'geo' AS tbl, (SELECT COUNT(*) FROM dbo.stg_geo) AS staging_rows, (SELECT COUNT(*) FROM dbo.fact_geo) AS typed_rows
UNION ALL SELECT 'az_provider', (SELECT COUNT(*) FROM dbo.stg_az_provider), (SELECT COUNT(*) FROM dbo.fact_az_provider);

-- B. loaded vs source_totals.csv
WITH src AS (
    SELECT CAST(yr AS INT) AS yr, dataset, SUM(CAST(source_rows AS BIGINT)) AS source_rows,
           SUM(CAST(source_srvcs AS FLOAT)) AS source_srvcs
    FROM dbo.stg_source_totals WHERE dataset IN ('geo','az_provider') GROUP BY CAST(yr AS INT), dataset
),
loaded AS (
    SELECT yr, 'geo' AS dataset, COUNT(*) AS loaded_rows, SUM(tot_srvcs) AS loaded_srvcs FROM dbo.fact_geo GROUP BY yr
    UNION ALL SELECT yr, 'az_provider', COUNT(*), SUM(srvcs) FROM dbo.fact_az_provider GROUP BY yr
)
SELECT l.yr, l.dataset, a.source_rows, l.loaded_rows, a.source_srvcs, l.loaded_srvcs,
       CASE WHEN a.source_rows = l.loaded_rows AND ABS(a.source_srvcs - l.loaded_srvcs) < 1 THEN 'MATCH' ELSE 'DIFF' END AS status
FROM loaded l LEFT JOIN src a ON a.yr = l.yr AND a.dataset = l.dataset
ORDER BY l.dataset, l.yr;

-- B2. 99201 rows seen in the raw geography files and dropped at pull time (0 rows of 99201 are loaded)
SELECT CAST(s.yr AS INT) AS yr, CAST(s.source_rows AS INT) AS raw_99201_rows_dropped,
       (SELECT COUNT(*) FROM dbo.fact_geo f WHERE f.yr = CAST(s.yr AS INT) AND f.hcpcs_cd = '99201') AS loaded_99201_rows
FROM dbo.stg_source_totals s WHERE s.dataset = 'geo_dropped_99201' ORDER BY 1;

-- C. National row vs sum of State rows (services)
SELECT n.yr, n.nat_services, s.state_sum_services,
       CAST(100.0 * (s.state_sum_services - n.nat_services) / n.nat_services AS DECIMAL(6,3)) AS pct_diff
FROM (SELECT yr, SUM(tot_srvcs) AS nat_services FROM dbo.fact_geo WHERE geo_level = 'National' GROUP BY yr) n
JOIN (SELECT yr, SUM(tot_srvcs) AS state_sum_services FROM dbo.fact_geo WHERE geo_level = 'State' GROUP BY yr) s ON s.yr = n.yr
ORDER BY n.yr;

-- D. Arizona provider file vs geography file
SELECT p.yr, p.az_prov, g.az_geo,
       CAST(100.0 * (p.az_prov - g.az_geo) / g.az_geo AS DECIMAL(6,3)) AS pct_diff
FROM (SELECT yr, SUM(srvcs) AS az_prov FROM dbo.fact_az_provider GROUP BY yr) p
JOIN (SELECT yr, SUM(tot_srvcs) AS az_geo FROM dbo.fact_geo WHERE geo_desc = 'Arizona' GROUP BY yr) g ON g.yr = p.yr
ORDER BY p.yr;
