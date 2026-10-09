-- 01_level_mix_by_specialty.sql
-- Question: How are office visits spread across E/M levels?
--  A. Arizona specialties (AZ provider file; only 2019 and 2024 exist): % of each specialty's
--     established and new visits at each level.  Change @yr (2019 or 2024).
--  B. National mix by code, all years (geography file).
USE Coding_Intensity;
SET NOCOUNT ON;
DECLARE @yr INT = 2024;

-- A1. Established patients, biggest AZ specialties
SELECT TOP 15
    specialty,
    MAX(patient_type_srvcs)                                              AS est_visits,
    CAST(SUM(CASE WHEN hcpcs_cd = '99211' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99211,
    CAST(SUM(CASE WHEN hcpcs_cd = '99212' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99212,
    CAST(SUM(CASE WHEN hcpcs_cd = '99213' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99213,
    CAST(SUM(CASE WHEN hcpcs_cd = '99214' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99214,
    CAST(SUM(CASE WHEN hcpcs_cd = '99215' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99215
FROM dbo.v_specialty_benchmark
WHERE yr = @yr AND patient_type = 'Established'
GROUP BY specialty
ORDER BY MAX(patient_type_srvcs) DESC;

-- A2. New patients, biggest AZ specialties
SELECT TOP 15
    specialty,
    MAX(patient_type_srvcs)                                              AS new_visits,
    CAST(SUM(CASE WHEN hcpcs_cd = '99202' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99202,
    CAST(SUM(CASE WHEN hcpcs_cd = '99203' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99203,
    CAST(SUM(CASE WHEN hcpcs_cd = '99204' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99204,
    CAST(SUM(CASE WHEN hcpcs_cd = '99205' THEN pct_of_patient_type END) AS DECIMAL(5,1)) AS pct_99205
FROM dbo.v_specialty_benchmark
WHERE yr = @yr AND patient_type = 'New'
GROUP BY specialty
ORDER BY MAX(patient_type_srvcs) DESC;

-- B. National services by code and year (geography file, both places of service)
SELECT yr,
       SUM(CASE WHEN hcpcs_cd = '99202' THEN tot_srvcs END) AS s_99202,
       SUM(CASE WHEN hcpcs_cd = '99203' THEN tot_srvcs END) AS s_99203,
       SUM(CASE WHEN hcpcs_cd = '99204' THEN tot_srvcs END) AS s_99204,
       SUM(CASE WHEN hcpcs_cd = '99205' THEN tot_srvcs END) AS s_99205,
       SUM(CASE WHEN hcpcs_cd = '99211' THEN tot_srvcs END) AS s_99211,
       SUM(CASE WHEN hcpcs_cd = '99212' THEN tot_srvcs END) AS s_99212,
       SUM(CASE WHEN hcpcs_cd = '99213' THEN tot_srvcs END) AS s_99213,
       SUM(CASE WHEN hcpcs_cd = '99214' THEN tot_srvcs END) AS s_99214,
       SUM(CASE WHEN hcpcs_cd = '99215' THEN tot_srvcs END) AS s_99215
FROM dbo.v_em_fact
WHERE geo_level = 'National'
GROUP BY yr ORDER BY yr;
