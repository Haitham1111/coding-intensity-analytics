-- 00_setup_database.sql -- run once before 01..08
-- Server: .\SQLEXPRESS | Creates database Coding_Intensity and loads the CMS E/M CSVs
-- staged by python\01_pull_cms.py into C:\Users\Public\coding_intensity (SQL Server cannot read Downloads).
-- Run: sqlcmd -S .\SQLEXPRESS -C -i 00_setup_database.sql
-- Loaded: geography file 2017-2024 (national + state); Arizona provider file 2019 and 2024 ONLY (by design).
-- Re-runnable: tables are dropped and rebuilt.

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Coding_Intensity')
    CREATE DATABASE Coding_Intensity;
GO

USE Coding_Intensity;
GO

------------------------------------------------------------------------------
-- 1. STAGING TABLES (everything as text, exactly as the CSV arrives)
--    src_year is filled after each BULK INSERT (one file per year).
--    The *_load views hide src_year so BULK INSERT maps CSV columns 1:1.
------------------------------------------------------------------------------
DROP VIEW  IF EXISTS dbo.v_outlier_counts, dbo.v_specialty_benchmark, dbo.v_em_fact, dbo.stg_geo_load, dbo.stg_az_provider_load, dbo.stg_prov_agg_load;
DROP TABLE IF EXISTS dbo.stg_geo, dbo.stg_az_provider, dbo.stg_prov_agg, dbo.stg_source_totals, dbo.fact_prov_agg;
GO

CREATE TABLE dbo.stg_geo (                      -- CMS "by Geography and Service"
    Rndrng_Prvdr_Geo_Lvl VARCHAR(20), Rndrng_Prvdr_Geo_Cd VARCHAR(10), Rndrng_Prvdr_Geo_Desc VARCHAR(60),
    HCPCS_Cd VARCHAR(10), Place_Of_Srvc VARCHAR(2), Tot_Rndrng_Prvdrs VARCHAR(20), Tot_Benes VARCHAR(20),
    Tot_Srvcs VARCHAR(20), Avg_Mdcr_Alowd_Amt VARCHAR(30), Avg_Mdcr_Pymt_Amt VARCHAR(30),
    src_year INT NULL);

CREATE TABLE dbo.stg_az_provider (              -- CMS "by Provider and Service", Arizona, NO NPI/names
    provider_sk VARCHAR(20), Rndrng_Prvdr_State_Abrvtn VARCHAR(5), Rndrng_Prvdr_Type VARCHAR(100),
    HCPCS_Cd VARCHAR(10), Place_Of_Srvc VARCHAR(2), Tot_Benes VARCHAR(20), Tot_Srvcs VARCHAR(20),
    Avg_Mdcr_Alowd_Amt VARCHAR(30), Avg_Mdcr_Pymt_Amt VARCHAR(30), src_year INT NULL);

CREATE TABLE dbo.stg_source_totals (            -- rows / services counted in the raw CMS file at pull time
    yr VARCHAR(10), dataset VARCHAR(30), hcpcs_cd VARCHAR(10), source_rows VARCHAR(20), source_srvcs VARCHAR(40));
GO

CREATE VIEW dbo.stg_geo_load AS
    SELECT Rndrng_Prvdr_Geo_Lvl, Rndrng_Prvdr_Geo_Cd, Rndrng_Prvdr_Geo_Desc, HCPCS_Cd, Place_Of_Srvc,
           Tot_Rndrng_Prvdrs, Tot_Benes, Tot_Srvcs, Avg_Mdcr_Alowd_Amt, Avg_Mdcr_Pymt_Amt FROM dbo.stg_geo;
GO
CREATE VIEW dbo.stg_az_provider_load AS
    SELECT provider_sk, Rndrng_Prvdr_State_Abrvtn, Rndrng_Prvdr_Type, HCPCS_Cd, Place_Of_Srvc,
           Tot_Benes, Tot_Srvcs, Avg_Mdcr_Alowd_Amt, Avg_Mdcr_Pymt_Amt FROM dbo.stg_az_provider;
GO
------------------------------------------------------------------------------
-- 2. BULK INSERT one file per year (dynamic SQL because BULK INSERT needs a literal path)
------------------------------------------------------------------------------
-- Geography file: every year 2017-2024
DECLARE @yr INT = 2017, @sql NVARCHAR(MAX);
WHILE @yr <= 2024
BEGIN
    SET @sql = N'
    BULK INSERT dbo.stg_geo_load FROM ''C:\Users\Public\coding_intensity\geo_' + CAST(@yr AS NVARCHAR(4)) + N'.csv''
        WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', CODEPAGE = ''65001'', TABLOCK);
    UPDATE dbo.stg_geo SET src_year = ' + CAST(@yr AS NVARCHAR(4)) + N' WHERE src_year IS NULL;';
    EXEC sp_executesql @sql;
    SET @yr += 1;
END;

-- Arizona provider file: ONLY 2019 (baseline) and 2024 (newest) exist
SET @yr = 2019;
WHILE @yr <= 2024
BEGIN
    SET @sql = N'
    BULK INSERT dbo.stg_az_provider_load FROM ''C:\Users\Public\coding_intensity\az_provider_' + CAST(@yr AS NVARCHAR(4)) + N'.csv''
        WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', CODEPAGE = ''65001'', TABLOCK);
    UPDATE dbo.stg_az_provider SET src_year = ' + CAST(@yr AS NVARCHAR(4)) + N' WHERE src_year IS NULL;';
    EXEC sp_executesql @sql;
    SET @yr += 5;                                  -- 2019 -> 2024
END;
GO

BULK INSERT dbo.stg_source_totals FROM 'C:\Users\Public\coding_intensity\source_totals.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
GO

------------------------------------------------------------------------------
-- 3. TYPED FACT TABLES
------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.fact_geo, dbo.fact_az_provider, dbo.dim_em_code;

-- Code dimension: patient type + level. 99211 has no history/exam requirement, treated as level 1.
CREATE TABLE dbo.dim_em_code (
    hcpcs_cd     VARCHAR(10) PRIMARY KEY,
    patient_type VARCHAR(12) NOT NULL,   -- 'New' or 'Established'
    em_level     TINYINT     NOT NULL,   -- 1..5 (the last digit of the CPT code)
    is_high_level BIT        NOT NULL    -- 1 for 99204/99205 and 99214/99215
);
INSERT INTO dbo.dim_em_code VALUES
 ('99202','New',2,0),('99203','New',3,0),('99204','New',4,1),('99205','New',5,1),
 ('99211','Established',1,0),('99212','Established',2,0),('99213','Established',3,0),
 ('99214','Established',4,1),('99215','Established',5,1);

-- Geography benchmark (national + state rows). Blank numbers become NULL via TRY_CAST.
SELECT src_year AS yr,
       Rndrng_Prvdr_Geo_Lvl AS geo_level, Rndrng_Prvdr_Geo_Cd AS geo_code, Rndrng_Prvdr_Geo_Desc AS geo_desc,
       HCPCS_Cd AS hcpcs_cd, Place_Of_Srvc AS pos,
       TRY_CAST(Tot_Rndrng_Prvdrs AS BIGINT) AS tot_providers,
       TRY_CAST(Tot_Benes AS BIGINT)         AS tot_benes,
       TRY_CAST(Tot_Srvcs AS DECIMAL(18,1))  AS tot_srvcs,
       TRY_CAST(Avg_Mdcr_Alowd_Amt AS DECIMAL(12,4)) AS avg_allowed,
       TRY_CAST(Avg_Mdcr_Pymt_Amt  AS DECIMAL(12,4)) AS avg_payment
INTO dbo.fact_geo FROM dbo.stg_geo
WHERE HCPCS_Cd IN ('99202','99203','99204','99205','99211','99212','99213','99214','99215');  -- valid 9 codes only

-- Arizona provider rows. provider_sk is a sequential surrogate (no NPI, no name anywhere).
SELECT src_year AS yr, CAST(provider_sk AS INT) AS provider_sk,
       Rndrng_Prvdr_State_Abrvtn AS state, Rndrng_Prvdr_Type AS specialty,
       HCPCS_Cd AS hcpcs_cd, Place_Of_Srvc AS pos,
       CAST(Tot_Benes AS INT) AS benes, CAST(Tot_Srvcs AS DECIMAL(12,1)) AS srvcs,
       CAST(Avg_Mdcr_Alowd_Amt AS DECIMAL(12,4)) AS avg_allowed,
       CAST(Avg_Mdcr_Pymt_Amt  AS DECIMAL(12,4)) AS avg_payment
INTO dbo.fact_az_provider FROM dbo.stg_az_provider
WHERE HCPCS_Cd IN ('99202','99203','99204','99205','99211','99212','99213','99214','99215');
GO

------------------------------------------------------------------------------
-- 4. VIEWS
------------------------------------------------------------------------------
-- v_em_fact: geography fact (national + state rows) with the code dimension attached.
-- total_payment / total_allowed = average amount x services (so sums can be re-averaged correctly).
CREATE OR ALTER VIEW dbo.v_em_fact AS
SELECT f.yr, f.geo_level, f.geo_desc, f.hcpcs_cd, f.pos,
       c.patient_type, c.em_level, c.is_high_level,
       CASE WHEN f.yr < 2021 THEN 'Pre-2021 rules' ELSE '2021+ rules' END AS coding_era,
       f.tot_providers, f.tot_benes, f.tot_srvcs,
       f.avg_allowed, f.avg_payment,
       f.avg_allowed * f.tot_srvcs AS total_allowed,
       f.avg_payment * f.tot_srvcs AS total_payment
FROM dbo.fact_geo AS f
JOIN dbo.dim_em_code AS c ON c.hcpcs_cd = f.hcpcs_cd;
GO

-- v_specialty_benchmark: Arizona specialty level mix (from the AZ provider file; 2019 and 2024 only).
-- pct_of_patient_type = this code's share of that specialty's new (or established) visits.
CREATE OR ALTER VIEW dbo.v_specialty_benchmark AS
WITH by_code AS (
    SELECT p.yr, p.specialty, c.patient_type, p.hcpcs_cd, c.em_level, c.is_high_level,
           SUM(p.srvcs) AS srvcs, SUM(p.srvcs * p.avg_payment) AS payment
    FROM dbo.fact_az_provider AS p
    JOIN dbo.dim_em_code AS c ON c.hcpcs_cd = p.hcpcs_cd
    GROUP BY p.yr, p.specialty, c.patient_type, p.hcpcs_cd, c.em_level, c.is_high_level
)
SELECT yr, specialty, patient_type, hcpcs_cd, em_level, is_high_level, srvcs, payment,
       SUM(srvcs) OVER (PARTITION BY yr, specialty, patient_type) AS patient_type_srvcs,
       100.0 * srvcs / NULLIF(SUM(srvcs) OVER (PARTITION BY yr, specialty, patient_type), 0) AS pct_of_patient_type
FROM by_code;
GO

-- v_outlier_counts: COUNTS ONLY of Arizona providers per specialty and year whose established
-- 99214/99215 share is > 2 SD above (high) or < -2 SD below (low) the specialty peer mean.
-- Same logic as 07_outlier_counts_by_specialty.sql. Providers need >= 100 established visits;
-- specialty-year needs >= 10 such peers. No provider ids are exposed. Outliers = statistical variance,
-- NOT evidence of fraud or upcoding.
CREATE OR ALTER VIEW dbo.v_outlier_counts AS
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
SELECT yr, specialty, MAX(peers) AS providers_in_scope,
       SUM(CASE WHEN z_score >  2 THEN 1 ELSE 0 END) AS high_outliers,
       SUM(CASE WHEN z_score < -2 THEN 1 ELSE 0 END) AS low_outliers
FROM z
GROUP BY yr, specialty
HAVING MAX(peers) >= 10;
GO
-- Sanity check: rows per table / view.
SELECT 'stg_geo' AS tbl, COUNT(*) AS n FROM dbo.stg_geo UNION ALL
SELECT 'stg_az_provider', COUNT(*) FROM dbo.stg_az_provider UNION ALL
SELECT 'fact_geo', COUNT(*) FROM dbo.fact_geo UNION ALL
SELECT 'fact_az_provider', COUNT(*) FROM dbo.fact_az_provider UNION ALL
SELECT 'v_em_fact', COUNT(*) FROM dbo.v_em_fact UNION ALL
SELECT 'v_specialty_benchmark', COUNT(*) FROM dbo.v_specialty_benchmark UNION ALL
SELECT 'v_outlier_counts', COUNT(*) FROM dbo.v_outlier_counts;
GO
