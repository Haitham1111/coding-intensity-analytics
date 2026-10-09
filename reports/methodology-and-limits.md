# Methodology and limits

Labels: **[Known]** = documented by CMS or verified in this project's data. **[Assumed]** = my interpretation, not verified.

## What this is
Office-visit E/M levels (valid codes only: 99202-99205 new patient, 99211-99215 established patient) by year, state and specialty.
Arizona vs national. The 2021 office-visit overhaul.

## Data
- By Geography and Service, 2017-2024, national + state rows, both places of service (O = office, F = facility). [Known]
- By Provider and Service, **Arizona only, 2019 and 2024 only, by design** (2019 = last full pre-overhaul year; 2024 = newest). [Known]
- Newest published year in the data.cms.gov catalog on 2026-10-09 is 2024 for both datasets. [Known] All "latest" results mean 2024.
- Specialty-level results exist only for Arizona and only for 2019 and 2024. There is no national or other-state specialty data in this project. [Known]
- Medicare fee-for-service only (Part B). Medicare Advantage, Medicaid and commercial visits are not in the data. [Known]

## Privacy
- Specialty level only. No NPIs, provider names or addresses are stored, queried or reported.
- Arizona provider rows carry a sequential surrogate id (1, 2, 3...), used only to group a provider's own rows. It is never returned by any query or report and does not map back to any person. [Known]

## Method
- Coding intensity = share of visits at the two highest levels: 99214+99215 of established visits, 99204+99205 of new-patient visits.
- Average payment per visit = SUM(average payment x services) / SUM(services) (service-weighted).
- Provider peer comparison (queries 03, 07): provider's % of established visits at 99214/99215 vs same specialty in Arizona, same year; providers need at least 100 established visits; z-score, percentile rank and deciles. Outlier = |z| > 2.
- 99201 handling: the 2017-2020 raw geography files contain 99201 rows (111, 110, 109, 108 rows in 2017-2020; none from 2021). They are dropped at pull time and the SQL load filters to the 9 valid codes, so 0 rows of 99201 are loaded. [Known]

## Limits
1. **Outliers are statistical variance, not evidence of fraud or upcoding.** A high share can reflect patient mix, referral patterns, small volume, or practice style. Many providers sit at exactly 0% or 100% because of low volume. Because shares are capped at 100%, the distribution is skewed, so z > 2 fires rarely for specialties where most providers are near the top (and z < -2 fires instead). [Known]
2. **2021 series break.** 99201 was deleted, and from 2021 office visits are leveled by medical decision making (MDM) or total time instead of history/exam. Compare 2020 to 2021 as a rule change plus behavior, not behavior alone. A rise in 99214/99215 share after 2021 is partly expected from the rule design. [Known: rule change. Assumed: how much of the rise is documentation/coding catch-up vs. patient complexity.]
3. **CMS suppression.** Cells with 10 or fewer beneficiaries are not published. Small specialties and small cells are under-counted. The Arizona provider file sums to about 2.5% (2019) and 2.9% (2024) fewer services than the geography file's Arizona rows. [Known: measured. Assumed: suppression is the main cause.]
4. **Provider files are limited to Arizona 2019 and 2024.** No other states, no other years, no year-by-year provider trends. Specialty movers compare only these two years. [Known]
5. **Place of service is mixed.** Facility (F) and office (O) payments differ; payment-per-visit mixes both. [Known]
6. **Specialty labels** are the CMS provider type as billed, and change in coverage over time (68 types in 2019, 74 in 2024 in the Arizona file). [Known]
7. 2020 is a pandemic year (services fell about 17% vs 2019 nationally in the geography file). [Known: measured.]
8. Population is Medicare fee-for-service beneficiaries; results do not generalize to all patients. [Known]
9. Sample reconciliation: loaded rows and service totals tie exactly to the staged CSVs (`sql/results/08_reconciliation.txt`, `python/validation_output.txt`). The 2024 Arizona "source" totals were counted from the staged CSV (the raw 2024 file was not re-downloaded); the 2019 totals were counted from the raw file at pull time. [Known]
