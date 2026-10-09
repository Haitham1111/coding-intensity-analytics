"""
01_pull_cms.py  --  Pull CMS Medicare Physician & Other Practitioners data, keep only office-visit E/M rows.

FINAL STRATEGY (no multi-GB national provider downloads):
  1. GEO  (all years 2017-2024): "By Geography and Service" CSV (national + state rows, tens of MB). Streamed in
          chunks (pandas chunksize), filtered to the 9 valid codes, written as geo_<year>.csv.
          99201 (and any other non-listed code) is DROPPED by the filter; the number of dropped 99201 rows
          per year is counted and written to source_totals.csv (dataset = geo_dropped_99201).
  2. AZ provider rows, ONLY 2019 (pre-overhaul baseline) and 2024 (newest published year): "By Provider and
          Service" is streamed in chunks, Arizona rows are kept, NPI is used only to build a sequential
          surrogate id (provider_sk) and is dropped; names/addresses are never loaded (usecols).
          Written as az_provider_<year>.csv.
  3. The all-state provider aggregate (prov_agg_*) is NOT part of the final design and is not built here.

Which runs were done for the final data set (flags below, change them to re-run):
  GEO_YEARS = 2017..2024      -> run (geo is small)
  AZ_PROVIDER_YEARS = 2019, 2024 -> run earlier; NOT re-run (multi-GB). Pass "az" on the command line to redo.
  (az_provider_2017/2018/2020 and prov_agg_* on disk came from an abandoned attempt and are not used.)

Newest year: the data.cms.gov catalog (data.json) lists 2024 as the newest "by Geography and Service" and
"by Provider and Service" year (checked 2026-10-09).

Usage:  python 01_pull_cms.py              -> geo, all GEO_YEARS (default, small)
        python 01_pull_cms.py geo 2023     -> geo, listed years only
        python 01_pull_cms.py az           -> Arizona provider files for AZ_PROVIDER_YEARS (BIG downloads)
Progress lines are printed with flush=True for every chunk.
"""
import json
import os
import sys
import time
import requests
import pandas as pd

OUT_DIR = r"C:\Users\Public\coding_intensity"
RAW_DIR = os.path.join(OUT_DIR, "raw")
CATALOG = "https://data.cms.gov/data.json"
GEO_YEARS = [2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024]   # newest published in the catalog = 2024
AZ_PROVIDER_YEARS = [2019, 2024]                                # baseline + newest only (by design)
CODES = ["99202", "99203", "99204", "99205", "99211", "99212", "99213", "99214", "99215"]
STATE = "AZ"
CHUNK = 200_000

# Column names verified against the file headers (the script checks them again at run time).
GEO_COLS = ["Rndrng_Prvdr_Geo_Lvl", "Rndrng_Prvdr_Geo_Cd", "Rndrng_Prvdr_Geo_Desc", "HCPCS_Cd",
            "Place_Of_Srvc", "Tot_Rndrng_Prvdrs", "Tot_Benes", "Tot_Srvcs",
            "Avg_Mdcr_Alowd_Amt", "Avg_Mdcr_Pymt_Amt"]
PROV_COLS = ["Rndrng_Prvdr_State_Abrvtn", "Rndrng_Prvdr_Type", "HCPCS_Cd", "Place_Of_Srvc",
             "Tot_Benes", "Tot_Srvcs", "Avg_Mdcr_Alowd_Amt", "Avg_Mdcr_Pymt_Amt"]
NUM = ["Tot_Benes", "Tot_Srvcs", "Avg_Mdcr_Alowd_Amt", "Avg_Mdcr_Pymt_Amt"]

TITLE_PROV = "Medicare Physician & Other Practitioners - by Provider and Service"
TITLE_GEO = "Medicare Physician & Other Practitioners - by Geography and Service"


def catalog_urls():
    """Return {('prov'|'geo', year): (csv_url, dataset_uuid)} from the data.cms.gov catalog."""
    data = requests.get(CATALOG, timeout=300).json()["dataset"]
    found = {}
    for d in data:
        title = d.get("title", "")
        kind = "prov" if title.startswith(TITLE_PROV) else "geo" if title.startswith(TITLE_GEO) else None
        if not kind:
            continue
        year = int(d["temporal"][0]["startDate"][:4]) if isinstance(d.get("temporal"), list) else None
        csv = [x["downloadURL"] for x in d.get("distribution", []) if x.get("format") == "CSV"]
        uuid = d["identifier"].split("/dataset/")[1].split("/")[0]
        if csv and year:
            found[(kind, year)] = (csv[0], uuid)
    return found


def download(url, path):
    """Stream a big file to disk; print MB downloaded every ~50 MB."""
    t0, got, next_print = time.time(), 0, 0
    with requests.get(url, stream=True, timeout=300) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length", 0))
        with open(path, "wb") as f:
            for block in r.iter_content(chunk_size=1024 * 1024):
                f.write(block)
                got += len(block)
                if got >= next_print:
                    print(f"   download {got/1e6:,.0f} MB of {total/1e6:,.0f} MB  ({got/1e6/max(time.time()-t0,1):.1f} MB/s)",
                          flush=True)
                    next_print += 50e6
    print(f"   download done: {got/1e6:,.0f} MB in {time.time()-t0:.0f}s", flush=True)


def check_header(path, need):
    cols = pd.read_csv(path, nrows=0).columns
    missing = [c for c in need if c not in cols]
    if missing:
        raise RuntimeError(f"columns not found in {path}: {missing}")


def pull_geo(year, url, totals):
    raw = os.path.join(RAW_DIR, f"geo_{year}_raw.csv")
    download(url, raw)
    check_header(raw, GEO_COLS)
    keep, n_read, n_kept, n_99201 = [], 0, 0, 0
    for chunk in pd.read_csv(raw, usecols=GEO_COLS, dtype=str, chunksize=CHUNK):
        n_read += len(chunk)
        n_99201 += int((chunk["HCPCS_Cd"] == "99201").sum())   # deleted code: counted, then dropped by the filter below
        chunk = chunk[chunk["HCPCS_Cd"].isin(CODES)]
        keep.append(chunk[GEO_COLS])
        n_kept += len(chunk)
        print(f"   geo {year}: read {n_read:,} kept {n_kept:,}", flush=True)
    df = pd.concat(keep, ignore_index=True)
    df.to_csv(os.path.join(OUT_DIR, f"geo_{year}.csv"), index=False)
    t = df.assign(s=pd.to_numeric(df["Tot_Srvcs"], errors="coerce")).groupby("HCPCS_Cd")["s"].agg(["size", "sum"])
    for code, row in t.iterrows():
        totals.append((year, "geo", code, int(row["size"]), float(row["sum"])))
    totals.append((year, "geo_dropped_99201", "99201", n_99201, 0.0))
    os.remove(raw)
    print(f"{year} geo: scanned {n_read:,} rows, kept {len(df):,}, 99201 rows dropped {n_99201:,}", flush=True)


def pull_az_provider(year, url, totals):
    """Stream the big provider file in chunks; keep Arizona E/M rows with a surrogate provider id."""
    raw = os.path.join(RAW_DIR, f"prov_{year}_raw.csv")
    download(url, raw)
    use = ["Rndrng_NPI"] + PROV_COLS          # the NPI is read ONLY to build the surrogate id
    check_header(raw, use)
    npi_to_sk, az_parts = {}, []
    n_read = n_az = 0
    az_rows, az_srvcs = {}, {}
    for chunk in pd.read_csv(raw, usecols=use, dtype=str, chunksize=CHUNK):
        n_read += len(chunk)
        chunk = chunk[(chunk["HCPCS_Cd"].isin(CODES)) & (chunk["Rndrng_Prvdr_State_Abrvtn"] == STATE)].copy()
        for c in NUM:
            chunk[c] = pd.to_numeric(chunk[c], errors="coerce")
        for npi in chunk["Rndrng_NPI"].unique():
            if npi not in npi_to_sk:
                npi_to_sk[npi] = len(npi_to_sk) + 1
        chunk["provider_sk"] = chunk["Rndrng_NPI"].map(npi_to_sk)
        az_parts.append(chunk[["provider_sk"] + PROV_COLS])
        n_az += len(chunk)
        for code, g in chunk.groupby("HCPCS_Cd"):
            az_rows[code] = az_rows.get(code, 0) + len(g)
            az_srvcs[code] = az_srvcs.get(code, 0) + g["Tot_Srvcs"].sum()
        print(f"   az provider {year}: read {n_read:,} rows, kept AZ E/M {n_az:,}", flush=True)
    az_all = pd.concat(az_parts, ignore_index=True)
    az_all.to_csv(os.path.join(OUT_DIR, f"az_provider_{year}.csv"), index=False)
    for code in sorted(az_rows):
        totals.append((year, "az_provider", code, az_rows[code], az_srvcs[code]))
    del npi_to_sk                              # the NPI-to-id mapping is never saved
    os.remove(raw)
    print(f"{year} AZ provider: scanned {n_read:,} rows; AZ E/M rows {len(az_all):,} "
          f"({az_all['provider_sk'].nunique():,} surrogate providers)", flush=True)


if __name__ == "__main__":
    os.makedirs(RAW_DIR, exist_ok=True)
    args = sys.argv[1:]
    mode = args.pop(0) if args and args[0] in ("geo", "az") else "geo"
    default_years = GEO_YEARS if mode == "geo" else AZ_PROVIDER_YEARS
    years = [int(a) for a in args] or default_years
    kind, fn = ("geo", pull_geo) if mode == "geo" else ("prov", pull_az_provider)
    dataset_names = ("geo", "geo_dropped_99201") if mode == "geo" else ("az_provider",)
    urls = catalog_urls()
    print("newest geo year in catalog:", max(y for (k, y) in urls if k == "geo"),
          "| newest provider year:", max(y for (k, y) in urls if k == "prov"), flush=True)
    tot_path = os.path.join(OUT_DIR, "source_totals.csv")
    old = pd.read_csv(tot_path, dtype={"hcpcs_cd": str}) if os.path.exists(tot_path) else pd.DataFrame()
    cols = ["year", "dataset", "hcpcs_cd", "source_rows", "source_srvcs"]
    for y in years:
        t0, totals = time.time(), []
        print(f"=== {y} {mode} ===", flush=True)
        url, uuid = urls[(kind, y)]
        print(f"{y} {kind}: {uuid}  {url}", flush=True)
        fn(y, url, totals)
        new = pd.DataFrame(totals, columns=cols)
        if len(old):   # replace this year's rows for the datasets just built; drop datasets no longer used
            old = old[~((old["year"] == y) & old["dataset"].isin(dataset_names))]
            old = old[old["dataset"].isin(["geo", "geo_dropped_99201", "az_provider"])]
        old = pd.concat([old, new], ignore_index=True)
        old.sort_values(["year", "dataset", "hcpcs_cd"]).to_csv(tot_path, index=False)
        print(f"=== {y} finished in {time.time()-t0:.0f}s ===", flush=True)
    print("done", flush=True)
