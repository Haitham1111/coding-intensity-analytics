"""
02_validate.py  --  Compare the staged CSVs with what is loaded in SQL Server (Coding_Intensity).
Checks per year: row counts and total services per HCPCS code, for the geography file (2017-2024) and the
Arizona provider file (2019, 2024 only). Also checks: only the 9 valid codes, zero 99201, no identity columns.
pyodbc is not installed here, so we call sqlcmd and read its CSV-style output.
Prints PASS / FAIL for every check and a summary at the end.
"""
import io
import subprocess
import pandas as pd

CSV_DIR = r"C:\Users\Public\coding_intensity"
YEARS = [2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024]   # geography file
AZ_YEARS = [2019, 2024]                                   # Arizona provider file
SERVER = r".\SQLEXPRESS"


def sql(query):
    """Run a query with sqlcmd and return a DataFrame."""
    cmd = ["sqlcmd", "-S", SERVER, "-C", "-d", "Coding_Intensity", "-s", ",", "-W",
           "-Q", "SET NOCOUNT ON; " + query]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    lines = [l for l in out.splitlines() if l.strip() and not set(l.strip()) <= set("-,")]  # drop ---- line
    return pd.read_csv(io.StringIO("\n".join(lines)), dtype={"hcpcs_cd": str})


results = []


def check(name, csv_value, sql_value, tol=0.5):
    ok = abs(float(csv_value) - float(sql_value)) <= tol
    results.append(ok)
    print(("PASS" if ok else "FAIL"), name, "csv =", csv_value, "sql =", sql_value)


# ---- SQL side: one query per data set, grouped by year and code
sql_geo = sql("SELECT yr, hcpcs_cd, COUNT(*) AS n, SUM(tot_srvcs) AS srvcs FROM fact_geo GROUP BY yr, hcpcs_cd")
sql_az = sql("SELECT yr, hcpcs_cd, COUNT(*) AS n, SUM(srvcs) AS srvcs FROM fact_az_provider GROUP BY yr, hcpcs_cd")
VALID = {"99202", "99203", "99204", "99205", "99211", "99212", "99213", "99214", "99215"}

for y in YEARS:
    # --- geography file (national + state rows)
    g = pd.read_csv(f"{CSV_DIR}/geo_{y}.csv", dtype={"HCPCS_Cd": str})
    g_codes = g.groupby("HCPCS_Cd").agg(n=("Tot_Srvcs", "size"), srvcs=("Tot_Srvcs", "sum"))
    s = sql_geo[sql_geo.yr == y].set_index("hcpcs_cd")
    check(f"{y} geo rows", g_codes.n.sum(), s.n.sum())
    for code in g_codes.index:
        check(f"{y} geo services {code}", g_codes.loc[code, "srvcs"], s.loc[code, "srvcs"])
    ok = set(g.HCPCS_Cd) == VALID and set(s.index) == VALID
    results.append(ok)
    print("PASS" if ok else "FAIL", f"{y} geo CSV and SQL contain exactly the 9 valid codes (99201 rows: {(g.HCPCS_Cd == '99201').sum()})")

for y in AZ_YEARS:
    # --- Arizona provider rows (only 2019 and 2024 exist by design)
    a = pd.read_csv(f"{CSV_DIR}/az_provider_{y}.csv", dtype={"HCPCS_Cd": str})
    a_codes = a.groupby("HCPCS_Cd").agg(n=("Tot_Srvcs", "size"), srvcs=("Tot_Srvcs", "sum"))
    s = sql_az[sql_az.yr == y].set_index("hcpcs_cd")
    check(f"{y} az rows", a_codes.n.sum(), s.n.sum())
    for code in a_codes.index:
        check(f"{y} az services {code}", a_codes.loc[code, "srvcs"], s.loc[code, "srvcs"])
    ok = set(a.HCPCS_Cd) == VALID and set(s.index) == VALID
    results.append(ok)
    print("PASS" if ok else "FAIL", f"{y} az CSV and SQL contain exactly the 9 valid codes")
    cols = a.columns.str.lower()
    bad = [c for c in cols if "npi" in c or "name" in c or "st1" in c or "city" in c]
    results.append(not bad)
    print("PASS" if not bad else "FAIL", f"{y} az file has no identity columns", bad)

print(f"\n{sum(results)} PASS / {len(results) - sum(results)} FAIL of {len(results)} checks")
print("OVERALL:", "PASS" if all(results) else "FAIL")
