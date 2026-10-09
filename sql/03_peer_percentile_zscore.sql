-- 03_peer_percentile_zscore.sql
-- Question: Inside Arizona, how spread out are providers of the same specialty on coding intensity?
-- Intensity = % of a provider's established visits billed as 99214/99215.
-- Peer group = same specialty AND same year (2019 and 2024 are the only provider years).
-- Output is counts/averages only. The surrogate provider id is used for grouping and never returned.
USE Coding_Intensity;
SET NOCOUNT ON;

WITH prov AS (                                   -- one row per provider x specialty x year
    SELECT yr, provider_sk, specialty,
           SUM(srvcs) AS est_visits,
           100.0 * SUM(CASE WHEN hcpcs_cd IN ('99214','99215') THEN srvcs ELSE 0 END) / SUM(srvcs) AS high_pct
    FROM dbo.fact_az_provider
    WHERE hcpcs_cd IN ('99211','99212','99213','99214','99215')
    GROUP BY yr, provider_sk, specialty
    HAVING SUM(srvcs) >= 100                     -- enough visits for a stable share
),
ranked AS (
    SELECT yr, specialty, high_pct,
           NTILE(10) OVER (PARTITION BY yr, specialty ORDER BY high_pct)      AS decile,
           PERCENT_RANK() OVER (PARTITION BY yr, specialty ORDER BY high_pct) AS pct_rank,
           (high_pct - AVG(high_pct) OVER (PARTITION BY yr, specialty))
               / NULLIF(STDEV(high_pct) OVER (PARTITION BY yr, specialty), 0)  AS z_score
    FROM prov
)
SELECT yr, specialty,
       COUNT(*)                                          AS providers,
       CAST(AVG(high_pct) AS DECIMAL(5,1))               AS avg_high_pct,
       CAST(STDEV(high_pct) AS DECIMAL(5,1))             AS sd_high_pct,
       CAST(MIN(high_pct) AS DECIMAL(5,1))               AS min_pct,
       CAST(MAX(high_pct) AS DECIMAL(5,1))               AS max_pct,
       SUM(CASE WHEN decile = 10 THEN 1 ELSE 0 END)      AS in_top_decile,
       SUM(CASE WHEN pct_rank >= 0.90 THEN 1 ELSE 0 END) AS at_or_above_p90,
       SUM(CASE WHEN ABS(z_score) > 2 THEN 1 ELSE 0 END) AS abs_z_gt_2
FROM ranked
GROUP BY yr, specialty
HAVING COUNT(*) >= 30
ORDER BY yr, COUNT(*) DESC;
