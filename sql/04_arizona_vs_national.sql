-- 04_arizona_vs_national.sql
-- Question: Does Arizona code higher or lower than the nation?
--  A. By year 2017-2024 (geography file): established 99214+99215 share and new 99204+99205 share.
--  B. AZ rank among states, each year.
--  C. Specialty view, 2019 and 2024 (AZ provider file only; no national specialty data is loaded).
USE Coding_Intensity;
SET NOCOUNT ON;

-- A. National vs Arizona by year
WITH g AS (
    SELECT yr, geo_desc,
           SUM(CASE WHEN hcpcs_cd IN ('99214','99215') THEN tot_srvcs END) AS high_visits,
           SUM(CASE WHEN hcpcs_cd LIKE '9921%'         THEN tot_srvcs END) AS est_visits,
           SUM(CASE WHEN hcpcs_cd IN ('99204','99205') THEN tot_srvcs END) AS new_high,
           SUM(CASE WHEN hcpcs_cd LIKE '9920%'         THEN tot_srvcs END) AS new_visits
    FROM dbo.fact_geo
    WHERE geo_desc IN ('National','Arizona')
    GROUP BY yr, geo_desc
)
SELECT n.yr,
       CAST(100.0 * n.high_visits / n.est_visits AS DECIMAL(5,2)) AS nat_est_high_pct,
       CAST(100.0 * a.high_visits / a.est_visits AS DECIMAL(5,2)) AS az_est_high_pct,
       CAST(100.0 * a.high_visits / a.est_visits - 100.0 * n.high_visits / n.est_visits AS DECIMAL(5,2)) AS est_gap_pp,
       CAST(100.0 * n.new_high / n.new_visits AS DECIMAL(5,2))    AS nat_new_high_pct,
       CAST(100.0 * a.new_high / a.new_visits AS DECIMAL(5,2))    AS az_new_high_pct,
       CAST(100.0 * a.new_high / a.new_visits - 100.0 * n.new_high / n.new_visits AS DECIMAL(5,2)) AS new_gap_pp
FROM g n JOIN g a ON a.yr = n.yr AND a.geo_desc = 'Arizona'
WHERE n.geo_desc = 'National'
ORDER BY n.yr;

-- B. AZ rank among states, each year (1 = highest established high-level share; states with >= 50,000 visits)
WITH st AS (
    SELECT yr, geo_desc,
           100.0 * SUM(CASE WHEN hcpcs_cd IN ('99214','99215') THEN tot_srvcs END)
                 / SUM(CASE WHEN hcpcs_cd LIKE '9921%' THEN tot_srvcs END) AS est_high_pct
    FROM dbo.fact_geo
    WHERE geo_level = 'State'
    GROUP BY yr, geo_desc
    HAVING SUM(CASE WHEN hcpcs_cd LIKE '9921%' THEN tot_srvcs END) >= 50000
),
r AS (SELECT yr, geo_desc, est_high_pct,
             RANK() OVER (PARTITION BY yr ORDER BY est_high_pct DESC) AS rnk,
             COUNT(*) OVER (PARTITION BY yr) AS n_states FROM st)
SELECT yr, rnk AS az_rank, n_states, CAST(est_high_pct AS DECIMAL(5,2)) AS az_est_high_pct
FROM r WHERE geo_desc = 'Arizona' ORDER BY yr;

-- C. Arizona specialties 2019 vs 2024: established high-level share (provider file, >= 5,000 visits)
WITH s AS (
    SELECT yr, specialty, SUM(srvcs) AS visits,
           100.0 * SUM(CASE WHEN is_high_level = 1 THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.v_specialty_benchmark
    WHERE patient_type = 'Established'
    GROUP BY yr, specialty
    HAVING SUM(srvcs) >= 5000
)
SELECT TOP 12 a.specialty, a.visits AS visits_2024,
       CAST(b.high_pct AS DECIMAL(5,1)) AS pct_2019, CAST(a.high_pct AS DECIMAL(5,1)) AS pct_2024
FROM s a LEFT JOIN s b ON b.specialty = a.specialty AND b.yr = 2019
WHERE a.yr = 2024
ORDER BY a.visits DESC;
