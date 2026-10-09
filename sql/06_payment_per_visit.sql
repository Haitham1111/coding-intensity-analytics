-- 06_payment_per_visit.sql
-- Question: What does Medicare pay on average per visit, by code, and how does Arizona compare?
-- total_payment = avg Medicare payment x services, so SUM(total_payment)/SUM(services) is a
-- service-weighted average (the right way to average an average).
-- Both places of service (office and facility) are included; the facility rate is lower.
USE Coding_Intensity;
SET NOCOUNT ON;
DECLARE @yr INT = (SELECT MAX(yr) FROM dbo.fact_geo);

-- A. By code: national 2019, national newest, Arizona newest
SELECT hcpcs_cd,
       CAST(SUM(CASE WHEN yr = 2019 AND geo_level = 'National' THEN total_payment END)
          / SUM(CASE WHEN yr = 2019 AND geo_level = 'National' THEN tot_srvcs END) AS DECIMAL(8,2)) AS nat_avg_pay_2019,
       CAST(SUM(CASE WHEN yr = @yr AND geo_level = 'National' THEN total_payment END)
          / SUM(CASE WHEN yr = @yr AND geo_level = 'National' THEN tot_srvcs END) AS DECIMAL(8,2)) AS nat_avg_pay_latest,
       CAST(SUM(CASE WHEN yr = @yr AND geo_desc = 'Arizona' THEN total_payment END)
          / SUM(CASE WHEN yr = @yr AND geo_desc = 'Arizona' THEN tot_srvcs END) AS DECIMAL(8,2)) AS az_avg_pay_latest
FROM dbo.v_em_fact
GROUP BY hcpcs_cd
ORDER BY hcpcs_cd;

-- B. Overall average payment per visit by year, National vs Arizona
SELECT yr, geo_desc,
       CAST(SUM(total_payment) / SUM(tot_srvcs) AS DECIMAL(8,2)) AS avg_pay_per_visit,
       CAST(SUM(total_payment) AS DECIMAL(20,0))                  AS total_medicare_payment
FROM dbo.v_em_fact
WHERE geo_desc IN ('National','Arizona')
GROUP BY yr, geo_desc
ORDER BY geo_desc DESC, yr;

-- C. Arizona by specialty, 2024 (provider file; payment per visit)
SELECT TOP 15 specialty, SUM(srvcs) AS visits,
       CAST(SUM(payment) / SUM(srvcs) AS DECIMAL(8,2)) AS avg_pay_per_visit
FROM dbo.v_specialty_benchmark
WHERE yr = 2024
GROUP BY specialty
ORDER BY SUM(srvcs) DESC;
