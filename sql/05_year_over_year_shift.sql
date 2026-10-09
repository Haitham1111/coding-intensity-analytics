-- 05_year_over_year_shift.sql
-- Question: How did the mix shift around the 2021 office-visit coding overhaul?
--  A. National and Arizona established/new mix by year 2017-newest (geography file)
--  B. Arizona specialty movers 2019 -> 2024 (AZ provider file; 2021 is not available at specialty level)
-- 2021 is a break in series (99201 deleted; history/exam dropped; leveling by MDM or time).
USE Coding_Intensity;
SET NOCOUNT ON;

-- A. Mix by year for National and Arizona
WITH nat AS (
    SELECT yr, geo_desc, hcpcs_cd, patient_type, SUM(tot_srvcs) AS srvcs
    FROM dbo.v_em_fact WHERE geo_desc IN ('National','Arizona')
    GROUP BY yr, geo_desc, hcpcs_cd, patient_type
),
tot AS (
    SELECT yr, geo_desc,
           SUM(CASE WHEN patient_type = 'Established' THEN srvcs END) AS est_visits,
           SUM(CASE WHEN patient_type = 'New'         THEN srvcs END) AS new_visits
    FROM nat GROUP BY yr, geo_desc
)
SELECT t.geo_desc, t.yr, t.est_visits,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd = '99212' THEN n.srvcs END) / t.est_visits AS DECIMAL(5,2)) AS pct_99212,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd = '99213' THEN n.srvcs END) / t.est_visits AS DECIMAL(5,2)) AS pct_99213,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd = '99214' THEN n.srvcs END) / t.est_visits AS DECIMAL(5,2)) AS pct_99214,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd = '99215' THEN n.srvcs END) / t.est_visits AS DECIMAL(5,2)) AS pct_99215,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd IN ('99214','99215') THEN n.srvcs END) / t.est_visits AS DECIMAL(5,2)) AS est_high_pct,
       CAST(100.0 * SUM(CASE WHEN n.hcpcs_cd IN ('99204','99205') THEN n.srvcs END) / t.new_visits AS DECIMAL(5,2)) AS new_high_pct
FROM nat n JOIN tot t ON t.yr = n.yr AND t.geo_desc = n.geo_desc
GROUP BY t.geo_desc, t.yr, t.est_visits, t.new_visits
ORDER BY t.geo_desc DESC, t.yr;

-- B. AZ specialty movers (established; >= 5,000 established visits in BOTH years)
WITH s AS (
    SELECT specialty, yr, SUM(srvcs) AS visits,
           100.0 * SUM(CASE WHEN is_high_level = 1 THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.v_specialty_benchmark
    WHERE patient_type = 'Established'
    GROUP BY specialty, yr
    HAVING SUM(srvcs) >= 5000
),
w AS (
    SELECT specialty,
           MAX(CASE WHEN yr = 2019 THEN high_pct END) AS p2019,
           MAX(CASE WHEN yr = 2024 THEN high_pct END) AS p2024,
           MAX(CASE WHEN yr = 2024 THEN visits END)   AS visits_2024,
           COUNT(*) AS yrs
    FROM s GROUP BY specialty
)
SELECT specialty, visits_2024,
       CAST(p2019 AS DECIMAL(5,1)) AS pct_2019, CAST(p2024 AS DECIMAL(5,1)) AS pct_2024,
       CAST(p2024 - p2019 AS DECIMAL(5,1)) AS chg_2019_2024_pp
FROM w WHERE yrs = 2
ORDER BY (p2024 - p2019) DESC;     -- biggest increases first; biggest decreases are at the bottom
