-- 02_high_level_share.sql
-- Question: What share of established visits are 99214+99215, and of new-patient visits 99204+99205?
--  A. Arizona specialties, 2019 vs 2024 (AZ provider file). Min 1,000 visits of that patient type.
--  B. States ranked on established high-level share, newest year (geography file).
USE Coding_Intensity;
SET NOCOUNT ON;

-- A. By AZ specialty, side by side (core "coding intensity" measure)
WITH share AS (
    SELECT yr, specialty, patient_type,
           SUM(srvcs)                                              AS visits,
           100.0 * SUM(CASE WHEN is_high_level = 1 THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.v_specialty_benchmark
    GROUP BY yr, specialty, patient_type
    HAVING SUM(srvcs) >= 1000
)
SELECT TOP 20 s24.patient_type, s24.specialty, s24.visits AS visits_2024,
       CAST(s19.high_pct AS DECIMAL(5,1)) AS high_pct_2019,
       CAST(s24.high_pct AS DECIMAL(5,1)) AS high_pct_2024
FROM share s24
LEFT JOIN share s19 ON s19.specialty = s24.specialty AND s19.patient_type = s24.patient_type AND s19.yr = 2019
WHERE s24.yr = 2024
ORDER BY s24.patient_type, s24.visits DESC;

-- B. States ranked, newest year, established 99214+99215 share (top 10 and bottom 5)
WITH st AS (
    SELECT geo_desc,
           SUM(tot_srvcs) AS est_visits,
           100.0 * SUM(CASE WHEN is_high_level = 1 THEN tot_srvcs ELSE 0 END) / SUM(tot_srvcs) AS high_pct
    FROM dbo.v_em_fact
    WHERE yr = (SELECT MAX(yr) FROM dbo.fact_geo) AND geo_level = 'State' AND patient_type = 'Established'
    GROUP BY geo_desc
    HAVING SUM(tot_srvcs) >= 50000                 -- drop tiny territories
),
r AS (SELECT geo_desc, est_visits, high_pct,
             RANK() OVER (ORDER BY high_pct DESC) AS rnk, COUNT(*) OVER () AS n FROM st)
SELECT rnk, n AS states_ranked, geo_desc, est_visits, CAST(high_pct AS DECIMAL(5,2)) AS est_high_pct
FROM r WHERE rnk <= 10 OR rnk > n - 5 OR geo_desc = 'Arizona'
ORDER BY rnk;
