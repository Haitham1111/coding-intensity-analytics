USE Coding_Intensity;
SET NOCOUNT ON;
PRINT '== 1. TABLES AND COLUMNS (INFORMATION_SCHEMA) ==';
SELECT c.TABLE_NAME, t.TABLE_TYPE, c.ORDINAL_POSITION AS pos, c.COLUMN_NAME, c.DATA_TYPE, c.CHARACTER_MAXIMUM_LENGTH AS max_len
FROM INFORMATION_SCHEMA.COLUMNS c JOIN INFORMATION_SCHEMA.TABLES t ON t.TABLE_NAME = c.TABLE_NAME
WHERE c.TABLE_SCHEMA = 'dbo' ORDER BY t.TABLE_TYPE, c.TABLE_NAME, c.ORDINAL_POSITION;
PRINT '== 2. ROW COUNTS PER TABLE / VIEW ==';
SELECT 'stg_geo' AS object_name, COUNT(*) AS n FROM dbo.stg_geo UNION ALL
SELECT 'stg_az_provider', COUNT(*) FROM dbo.stg_az_provider UNION ALL
SELECT 'stg_source_totals', COUNT(*) FROM dbo.stg_source_totals UNION ALL
SELECT 'dim_em_code', COUNT(*) FROM dbo.dim_em_code UNION ALL
SELECT 'fact_geo', COUNT(*) FROM dbo.fact_geo UNION ALL
SELECT 'fact_az_provider', COUNT(*) FROM dbo.fact_az_provider UNION ALL
SELECT 'v_em_fact', COUNT(*) FROM dbo.v_em_fact UNION ALL
SELECT 'v_specialty_benchmark', COUNT(*) FROM dbo.v_specialty_benchmark;
PRINT '== 3. ROWS PER YEAR ==';
SELECT 'fact_geo' AS tbl, yr, COUNT(*) AS n FROM dbo.fact_geo GROUP BY yr UNION ALL
SELECT 'fact_az_provider', yr, COUNT(*) FROM dbo.fact_az_provider GROUP BY yr ORDER BY 1, 2;
PRINT '== 4. HCPCS VALIDITY: DISTINCT codes in the facts (must be exactly the 9 codes) ==';
SELECT 'fact_geo' AS tbl, hcpcs_cd, COUNT(*) AS n FROM dbo.fact_geo GROUP BY hcpcs_cd
UNION ALL SELECT 'fact_az_provider', hcpcs_cd, COUNT(*) FROM dbo.fact_az_provider GROUP BY hcpcs_cd ORDER BY 1, 2;
SELECT (SELECT COUNT(DISTINCT hcpcs_cd) FROM dbo.fact_geo) AS distinct_codes_geo,
       (SELECT COUNT(DISTINCT hcpcs_cd) FROM dbo.fact_az_provider) AS distinct_codes_az,
       (SELECT COUNT(*) FROM dbo.fact_geo WHERE hcpcs_cd NOT IN (SELECT hcpcs_cd FROM dbo.dim_em_code)) AS geo_rows_not_in_9,
       (SELECT COUNT(*) FROM dbo.fact_az_provider WHERE hcpcs_cd NOT IN (SELECT hcpcs_cd FROM dbo.dim_em_code)) AS az_rows_not_in_9,
       (SELECT COUNT(*) FROM dbo.stg_geo WHERE HCPCS_Cd = '99201') + (SELECT COUNT(*) FROM dbo.stg_az_provider WHERE HCPCS_Cd = '99201')
       + (SELECT COUNT(*) FROM dbo.fact_geo WHERE hcpcs_cd = '99201') + (SELECT COUNT(*) FROM dbo.fact_az_provider WHERE hcpcs_cd = '99201') AS rows_99201;
