# Data sources

No data files are stored in this repo. `python/01_pull_cms.py` writes them to `C:\Users\Public\coding_intensity\` (SQL Server cannot read from Downloads); `sql/00_setup_database.sql` loads them.

Publisher: CMS, "Medicare Physician & Other Practitioners" public use files, catalog https://data.cms.gov/data.json
Newest published data year (checked 2026-10-09): **2024**.

| Dataset | Years used | Used for |
|---|---|---|
| By Geography and Service | 2017-2024 | National + state level mix, payment, Arizona vs national |
| By Provider and Service | **2019 and 2024 only, Arizona rows only** | Specialty mix, provider peer comparison (surrogate id) |

- By Geography and Service: https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-geography-and-service
- By Provider and Service: https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service
- Download URLs per year are read from the catalog by `python/01_pull_cms.py`.

Geography dataset UUIDs: 2017 8e96a9f2-ce6e-46fd-b30d-8c695c756bfd, 2018 05a85700-052f-4509-af43-7042b9b35868, 2019 673030ae-ceed-4561-8fca-b1275395a86a, 2020 31eb3018-43e0-4259-a0d8-e7a1112ffd08, 2021 f00f462f-bb61-48b1-a321-1c50d78ce175, 2022 87304f15-9ed0-41dc-a141-6141a0327453, 2023 ddee9e22-7889-4bef-975a-7853e4cd0fbb, 2024 6fea9d79-0129-4e4c-b1b8-23cd86a4f435.

Codes kept: 99202-99205 (new patient), 99211-99215 (established patient). 99201 (deleted in 2021) is present in the 2017-2020 raw geography files and is dropped.

Staged files (outside the repo): `geo_2017..2024.csv`, `az_provider_2019.csv`, `az_provider_2024.csv`, `source_totals.csv` (row/service counts for reconciliation, incl. dropped 99201 rows).
Other files in that folder (`az_provider_2017/2018/2020`, `prov_agg_*`, `api_totals.csv`) come from an abandoned attempt and are not used.

Identity fields (NPI, names, addresses) are never stored. Arizona provider rows carry only a sequential surrogate id.
Limits: see `reports/methodology-and-limits.md`.
