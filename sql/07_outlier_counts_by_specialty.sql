-- 07_outlier_counts_by_specialty.sql
-- Question: How many Arizona providers, per specialty, sit far above (or below) their peers on
-- coding intensity? COUNTS ONLY. No identifiers are selected; the surrogate id is not returned.
-- Intensity = share of a provider's established visits billed as 99214/99215.
-- Peer group = same specialty, same year (2019 or 2024), Arizona (>= 10 providers, each with >= 100 visits).
-- An outlier here is statistical variance (z > 2 or z < -2), NOT evidence of upcoding or fraud.
USE Coding_Intensity;
SET NOCOUNT ON;

-- A. By specialty and year (top 15 specialties by peer count, per year)
WITH prov AS (
    SELECT yr, provider_sk, specialty,
           100.0 * SUM(CASE WHEN hcpcs_cd IN ('99214','99215') THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.fact_az_provider
    WHERE hcpcs_cd IN ('99211','99212','99213','99214','99215')
    GROUP BY yr, provider_sk, specialty
    HAVING SUM(srvcs) >= 100
),
z AS (
    SELECT yr, specialty, high_pct,
           COUNT(*) OVER (PARTITION BY yr, specialty) AS peers,
           (high_pct - AVG(high_pct) OVER (PARTITION BY yr, specialty))
               / NULLIF(STDEV(high_pct) OVER (PARTITION BY yr, specialty), 0) AS z_score
    FROM prov
),
by_spec AS (
    SELECT yr, specialty, MAX(peers) AS providers,
           SUM(CASE WHEN z_score >  2 THEN 1 ELSE 0 END) AS high_outliers_z_gt_2,
           SUM(CASE WHEN z_score < -2 THEN 1 ELSE 0 END) AS low_outliers_z_lt_neg2,
           CAST(100.0 * SUM(CASE WHEN z_score > 2 THEN 1 ELSE 0 END) / MAX(peers) AS DECIMAL(4,1)) AS pct_high_outliers,
           ROW_NUMBER() OVER (PARTITION BY yr ORDER BY MAX(peers) DESC) AS rn
    FROM z
    GROUP BY yr, specialty
    HAVING MAX(peers) >= 10
)
SELECT yr, specialty, providers, high_outliers_z_gt_2, low_outliers_z_lt_neg2, pct_high_outliers
FROM by_spec
WHERE rn <= 15
ORDER BY yr, rn;

-- B. Totals by year (does the tail change between 2019 and 2024?)
WITH prov AS (
    SELECT yr, provider_sk, specialty,
           100.0 * SUM(CASE WHEN hcpcs_cd IN ('99214','99215') THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.fact_az_provider
    WHERE hcpcs_cd IN ('99211','99212','99213','99214','99215')
    GROUP BY yr, provider_sk, specialty
    HAVING SUM(srvcs) >= 100
),
z AS (
    SELECT yr, specialty,
           COUNT(*) OVER (PARTITION BY yr, specialty) AS peers,
           (high_pct - AVG(high_pct) OVER (PARTITION BY yr, specialty))
               / NULLIF(STDEV(high_pct) OVER (PARTITION BY yr, specialty), 0) AS z_score
    FROM prov
)
SELECT yr, COUNT(*) AS providers_in_scope,
       SUM(CASE WHEN z_score >  2 THEN 1 ELSE 0 END) AS high_outliers,
       SUM(CASE WHEN z_score < -2 THEN 1 ELSE 0 END) AS low_outliers
FROM z
WHERE peers >= 10
GROUP BY yr
ORDER BY yr;
