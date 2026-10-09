# DAX measures: E/M Coding Intensity Atlas

Model: `powerbi/coding-intensity-dashboard.pbix`. 32 measures in the `_Measures` table. Tables: `FactEM` (v_em_fact, national and state rows 2017-2024), `FactSpecialty` (v_specialty_benchmark, Arizona 2019 and 2024), `FactOutlier` (v_outlier_counts, counts only), `DimEM` (dim_em_code), `DimYear` and `DimSpecialty` (calculated). No provider id exists anywhere in the model.

## Rules every ratio or difference measure follows

- `VAR n = ...; VAR d = ...; RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )`.
- A BLANK value is never compared with `<` or `>` directly (`BLANK() < 3` is TRUE in DAX). Where a threshold is needed the value is first tested: `NOT ISBLANK ( x ) && x < 3`.
- A numerator that is BLANK only because no rows match is turned into 0 with `COALESCE ( ..., 0 )` once the denominator is known to exist. Otherwise a specialty with visits but no 99214/99215 would show BLANK instead of 0%.
- Share denominators remove code-level filters (`REMOVEFILTERS ( DimEM[hcpcs_cd], ... )`) so a code slicer cannot push a share above 100%.

## Measures

### Total Services

- Folder: 1 Volume | Format: `#,0`
- Purpose: National E/M office-visit services (valid 9 codes), national rows only.
- BLANK behavior: BLANK when no national rows exist in the filter context (e.g. a year outside 2017-2024). Never 0.

```dax
CALCULATE ( SUM ( FactEM[tot_srvcs] ), FactEM[geo_level] = "National" )
```

### Total Services (M)

- Folder: 1 Volume | Format: `#,0.0"M"`
- Purpose: National services in millions (chart-label helper; avoids custom-format scaling quirks).
- BLANK behavior: BLANK when Total Services is BLANK.

```dax
VAR x = [Total Services]
RETURN IF ( ISBLANK ( x ), BLANK (), DIVIDE ( x, 1000000 ) )
```

### Total Medicare Payment

- Folder: 1 Volume | Format: `$#,0.00,,,"B"`
- Purpose: National Medicare payment dollars (average payment x services).
- BLANK behavior: BLANK when no national rows exist.

```dax
CALCULATE ( SUM ( FactEM[total_payment] ), FactEM[geo_level] = "National" )
```

### Avg Payment per Visit

- Folder: 1 Volume | Format: `$#,0.00`
- Purpose: Service-weighted Medicare payment per visit (national).
- BLANK behavior: BLANK if payment or services is BLANK, or services = 0.

```dax
VAR n = [Total Medicare Payment]
VAR d = [Total Services]
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### Established Services

- Folder: 1 Volume | Format: `#,0`
- Purpose: National established-patient visits (99211-99215).
- BLANK behavior: BLANK if no established-patient rows are in context (e.g. code filter 99203).

```dax
CALCULATE ( [Total Services], DimEM[patient_type] = "Established" )
```

### New Services

- Folder: 1 Volume | Format: `#,0`
- Purpose: National new-patient visits (99202-99205).
- BLANK behavior: BLANK if no new-patient rows are in context.

```dax
CALCULATE ( [Total Services], DimEM[patient_type] = "New" )
```

### Services YoY %

- Folder: 1 Volume | Format: `+0.0%;-0.0%;0.0%`
- Purpose: Change in national services vs the prior year (needs a single-year context).
- BLANK behavior: BLANK for the first year (2017), when no single year is selected (SELECTEDVALUE), or when the prior year is BLANK/0.

```dax
VAR y = SELECTEDVALUE ( DimYear[yr] )
VAR cur = [Total Services]
VAR prev = CALCULATE ( [Total Services], DimYear[yr] = y - 1 )
VAR n = IF ( ISBLANK ( cur ) || ISBLANK ( prev ), BLANK (), cur - prev )
VAR d = prev
RETURN IF ( ISBLANK ( y ) || ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### Established 99214+99215 Share

- Folder: 2 National intensity | Format: `0.00%`
- Purpose: Share of established visits billed at the two highest levels (national).
- BLANK behavior: BLANK when there are no established visits. A real 0 (no 99214/5 rows but visits exist) returns 0%, not BLANK. Ignores any code-level filter, so it cannot exceed 100%.

```dax
VAR n = COALESCE ( CALCULATE ( [Total Services], DimEM[patient_type] = "Established", DimEM[hcpcs_cd] IN { "99214", "99215" } ), 0 )
VAR d = CALCULATE ( [Established Services], REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### New 99204+99205 Share

- Folder: 2 National intensity | Format: `0.00%`
- Purpose: Share of new-patient visits billed at the two highest levels (national).
- BLANK behavior: Same as the established share, for new-patient visits.

```dax
VAR n = COALESCE ( CALCULATE ( [Total Services], DimEM[patient_type] = "New", DimEM[hcpcs_cd] IN { "99204", "99205" } ), 0 )
VAR d = CALCULATE ( [New Services], REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### High-Level Share (All)

- Folder: 2 National intensity | Format: `0.00%`
- Purpose: High-level (99204/5 + 99214/5) visits as a share of all visits in the current patient-type context.
- BLANK behavior: BLANK when total services is BLANK. Respects a code filter (share of the filtered codes that are high level).

```dax
VAR n = COALESCE ( CALCULATE ( [Total Services], DimEM[is_high_level] = TRUE () ), 0 )
VAR d = [Total Services]
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### Level Share within Patient Type

- Folder: 2 National intensity | Format: `0.0%`
- Purpose: One code's share of its patient type's visits (used by the level-mix stacked columns).
- BLANK behavior: BLANK when the code has no rows that year (not 0). Denominator keeps the patient-type filter only.

```dax
VAR n = [Total Services]
VAR d = CALCULATE ( [Total Services], REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### National Established High Share

- Folder: 3 Arizona vs national | Format: `0.00%`
- Purpose: Same as Established 99214+99215 Share; named for the Arizona-vs-national legend.
- BLANK behavior: Same BLANK behavior as Established 99214+99215 Share.

```dax
VAR x = [Established 99214+99215 Share]
RETURN x
```

### AZ Established High Share

- Folder: 3 Arizona vs national | Format: `0.00%`
- Purpose: Arizona share of established visits at 99214/99215 (geography file, state row).
- BLANK behavior: BLANK if Arizona has no established rows in context (e.g. a year outside the data).

```dax
VAR n = COALESCE ( CALCULATE ( SUM ( FactEM[tot_srvcs] ), FactEM[geo_level] = "State", FactEM[geo_desc] = "Arizona", DimEM[patient_type] = "Established", DimEM[hcpcs_cd] IN { "99214", "99215" } ), 0 )
VAR d = CALCULATE ( SUM ( FactEM[tot_srvcs] ), FactEM[geo_level] = "State", FactEM[geo_desc] = "Arizona", DimEM[patient_type] = "Established", REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### AZ Gap vs National (pts)

- Folder: 3 Arizona vs national | Format: `+0.00" pts";-0.00" pts";0.00" pts"`
- Purpose: Arizona minus national established high-level share, in percentage points.
- BLANK behavior: BLANK if either side is BLANK. Never a gap against a missing value.

```dax
VAR a = [AZ Established High Share]
VAR b = [National Established High Share]
RETURN IF ( ISBLANK ( a ) || ISBLANK ( b ), BLANK (), ( a - b ) * 100 )
```

### State Est Visits

- Folder: 3 Arizona vs national | Format: `#,0`
- Purpose: Established visits summed over state rows (helper for the state ranking).
- BLANK behavior: BLANK if the state has no established rows.

```dax
CALCULATE ( SUM ( FactEM[tot_srvcs] ), FactEM[geo_level] = "State", DimEM[patient_type] = "Established" )
```

### State Est High Share

- Folder: 3 Arizona vs national | Format: `0.00%`
- Purpose: Established 99214+99215 share for the state in context; BLANK for states under 50,000 established visits (same cutoff as sql/04).
- BLANK behavior: BLANK for any state or territory under 50,000 established visits in the context (Guam 46,906 in 2024 is BLANK; Arizona is not).

```dax
VAR n = COALESCE ( CALCULATE ( SUM ( FactEM[tot_srvcs] ), FactEM[geo_level] = "State", DimEM[patient_type] = "Established", DimEM[hcpcs_cd] IN { "99214", "99215" } ), 0 )
VAR d = CALCULATE ( [State Est Visits], REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
VAR big = NOT ISBLANK ( d ) && d >= 50000
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0 || NOT big, BLANK (), DIVIDE ( n, d ) )
```

### AZ Rank

- Folder: 3 Arizona vs national | Format: `0`
- Purpose: Arizona's rank among states (1 = highest established 99214+99215 share), states with 50,000+ established visits; BLANK unless exactly one year is in context.
- BLANK behavior: BLANK unless exactly one year is in context (a pooled rank across years would be misleading), or when Arizona is not ranked.

```dax
VAR tbl =
    CALCULATETABLE (
        ADDCOLUMNS ( VALUES ( FactEM[geo_desc] ), "@sh", [State Est High Share] ),
        REMOVEFILTERS ( FactEM[geo_desc] ), FactEM[geo_level] = "State"
    )
VAR ranked = FILTER ( tbl, NOT ISBLANK ( [@sh] ) )
VAR az = MAXX ( FILTER ( ranked, [geo_desc] = "Arizona" ), [@sh] )
RETURN IF ( NOT HASONEVALUE ( DimYear[yr] ) || ISBLANK ( az ), BLANK (), COUNTROWS ( FILTER ( ranked, [@sh] > az ) ) + 1 )
```

### States Ranked

- Folder: 3 Arizona vs national | Format: `0`
- Purpose: Number of states in the ranking (50,000+ established visits).
- BLANK behavior: BLANK unless exactly one year is in context.

```dax
VAR tbl =
    CALCULATETABLE (
        ADDCOLUMNS ( VALUES ( FactEM[geo_desc] ), "@sh", [State Est High Share] ),
        REMOVEFILTERS ( FactEM[geo_desc] ), FactEM[geo_level] = "State"
    )
VAR n = COUNTROWS ( FILTER ( tbl, NOT ISBLANK ( [@sh] ) ) )
RETURN IF ( NOT HASONEVALUE ( DimYear[yr] ) || n = 0, BLANK (), n )
```

### State Bar Color

- Folder: 3 Arizona vs national | Format: `@`
- Purpose: Conditional-format helper: Arizona amber, other states sky blue.
- BLANK behavior: Text helper. Returns sky blue when no single state is in context.

```dax
IF ( SELECTEDVALUE ( FactEM[geo_desc] ) = "Arizona", "#F59E0B", "#38BDF8" )
```

### Spec Est Visits

- Folder: 4 Arizona specialties | Format: `#,0`
- Purpose: Arizona established visits by specialty (provider file; 2019 and 2024 only).
- BLANK behavior: BLANK for any year other than 2019 or 2024 (the Arizona provider file only has those two years).

```dax
CALCULATE ( SUM ( FactSpecialty[srvcs] ), DimEM[patient_type] = "Established" )
```

### Spec Est High Share

- Folder: 4 Arizona specialties | Format: `0.0%`
- Purpose: Arizona specialty share of established visits at 99214/99215 in the current year context.
- BLANK behavior: BLANK for 2017-2018, 2020-2023 (no provider data) and for a specialty with no established visits in that year.

```dax
VAR n = COALESCE ( CALCULATE ( SUM ( FactSpecialty[srvcs] ), DimEM[patient_type] = "Established", DimEM[hcpcs_cd] IN { "99214", "99215" } ), 0 )
VAR d = CALCULATE ( [Spec Est Visits], REMOVEFILTERS ( DimEM[hcpcs_cd], DimEM[em_level], DimEM[is_high_level] ) )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### 2019 Share

- Folder: 4 Arizona specialties | Format: `0.0%`
- Purpose: Specialty established 99214+99215 share in 2019 (BLANK if the specialty has no 2019 data).
- BLANK behavior: Fixed to 2019: ignores a year filter by design. BLANK if the specialty has no 2019 established visits. A specialty with visits but none at 99214/5 returns 0%.

```dax
CALCULATE ( [Spec Est High Share], DimYear[yr] = 2019 )
```

### 2024 Share

- Folder: 4 Arizona specialties | Format: `0.0%`
- Purpose: Specialty established 99214+99215 share in 2024 (BLANK if the specialty has no 2024 data).
- BLANK behavior: Fixed to 2024: ignores a year filter by design. BLANK if the specialty has no 2024 established visits.

```dax
CALCULATE ( [Spec Est High Share], DimYear[yr] = 2024 )
```

### Change 2019-2024 (pts)

- Folder: 4 Arizona specialties | Format: `+0.0" pts";-0.0" pts";0.0" pts"`
- Purpose: 2024 share minus 2019 share in points; BLANK unless both years have 5,000+ established visits.
- BLANK behavior: BLANK unless BOTH years have 5,000+ established visits (small specialties are not compared).

```dax
VAR s19 = [2019 Share]
VAR s24 = [2024 Share]
VAR v19 = CALCULATE ( [Spec Est Visits], DimYear[yr] = 2019 )
VAR v24 = CALCULATE ( [Spec Est Visits], DimYear[yr] = 2024 )
VAR enough = NOT ISBLANK ( v19 ) && NOT ISBLANK ( v24 ) && v19 >= 5000 && v24 >= 5000
RETURN IF ( ISBLANK ( s19 ) || ISBLANK ( s24 ) || NOT enough, BLANK (), ( s24 - s19 ) * 100 )
```

### Abs Change (pts)

- Folder: 4 Arizona specialties | Format: `0.0`
- Purpose: Absolute change, used only to rank the top movers.
- BLANK behavior: BLANK when the change is BLANK.

```dax
VAR c = [Change 2019-2024 (pts)]
RETURN IF ( ISBLANK ( c ), BLANK (), ABS ( c ) )
```

### Mover Color

- Folder: 4 Arizona specialties | Format: `@`
- Purpose: Conditional-format helper: increases teal, decreases red.
- BLANK behavior: Text helper. Red only when the change is non-blank and negative (BLANK is not treated as negative).

```dax
VAR c = [Change 2019-2024 (pts)]
RETURN IF ( NOT ISBLANK ( c ) && c < 0, "#EF4444", "#14B8A6" )
```

### AZ Payment per Visit

- Folder: 4 Arizona specialties | Format: `$#,0.00`
- Purpose: Service-weighted Medicare payment per visit for Arizona specialties (provider file).
- BLANK behavior: BLANK for years without provider data (2017-2018, 2020-2023) or when services is 0.

```dax
VAR n = SUM ( FactSpecialty[payment] )
VAR d = SUM ( FactSpecialty[srvcs] )
RETURN IF ( ISBLANK ( n ) || ISBLANK ( d ) || d = 0, BLANK (), DIVIDE ( n, d ) )
```

### Outlier Count High

- Folder: 5 Outliers | Format: `#,0`
- Purpose: Arizona providers more than 2 SD above their specialty peers (counts only; statistical variance, not fraud).
- BLANK behavior: BLANK when no outlier-view rows exist in context (2021, a specialty with fewer than 10 peers).

```dax
IF ( COUNTROWS ( FactOutlier ) = 0, BLANK (), SUM ( FactOutlier[high_outliers] ) )
```

### Outlier Count Low

- Folder: 5 Outliers | Format: `#,0`
- Purpose: Arizona providers more than 2 SD below their specialty peers (counts only).
- BLANK behavior: Same as Outlier Count High.

```dax
IF ( COUNTROWS ( FactOutlier ) = 0, BLANK (), SUM ( FactOutlier[low_outliers] ) )
```

### Outlier Count Total

- Folder: 5 Outliers | Format: `#,0`
- Purpose: High plus low outlier count (used to rank specialties).
- BLANK behavior: BLANK only when both counts are BLANK; otherwise high plus low (BLANK treated as 0 inside the sum).

```dax
VAR h = [Outlier Count High]
VAR l = [Outlier Count Low]
RETURN IF ( ISBLANK ( h ) && ISBLANK ( l ), BLANK (), COALESCE ( h, 0 ) + COALESCE ( l, 0 ) )
```

### Providers in Scope

- Folder: 5 Outliers | Format: `#,0`
- Purpose: Providers with 100+ established visits in specialty-years with 10+ such peers (aggregate count).
- BLANK behavior: BLANK when no outlier-view rows exist in context. Aggregate count only.

```dax
IF ( COUNTROWS ( FactOutlier ) = 0, BLANK (), SUM ( FactOutlier[providers_in_scope] ) )
```

### Top Mover Change (pts)

- Folder: 4 Arizona specialties | Format: `+0.0" pts";-0.0" pts";0.0" pts"`
- Purpose: Change 2019-2024 shown only for the 8 biggest increases and 5 biggest decreases among eligible specialties in the current selection; BLANK otherwise.
- BLANK behavior: BLANK unless the specialty is one of the 8 largest increases or 5 largest decreases among eligible specialties in the current selection.

```dax
VAR c = [Change 2019-2024 (pts)]
VAR tbl = ADDCOLUMNS ( ALLSELECTED ( DimSpecialty[specialty] ), "@c", [Change 2019-2024 (pts)] )
VAR valid = FILTER ( tbl, NOT ISBLANK ( [@c] ) )
VAR up = COUNTROWS ( FILTER ( valid, [@c] > c ) ) + 1
VAR down = COUNTROWS ( FILTER ( valid, [@c] < c ) ) + 1
RETURN IF ( ISBLANK ( c ), BLANK (), IF ( up <= 8 || down <= 5, c, BLANK () ) )
```

## BLANK test results

Every measure was run through DAX queries against the live model under filter contexts that produce BLANK. Result: 0 errors across all 32 measures in 5 grouped queries (by year, by specialty, by geography, by code x year, grand total), and no misleading 0 in the contexts below.

| Test | Filter context | Measure | Result | Verdict |
|---|---|---|---|---|
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Spec Est Visits | (BLANK) | BLANK, correct (no 2021 provider data) |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Spec Est High Share | (BLANK) | BLANK, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | 2019 Share | 0.5997 | Value by design: fixed-year measure ignores the year filter |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | 2024 Share | 0.6237 | Value by design: fixed-year measure ignores the year filter |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Change 2019-2024 (pts) | 2.4055 | Value by design (all specialties pooled) |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Abs Change (pts) | 2.4055 | Non-blank, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Top Mover Change (pts) | (BLANK) | BLANK, correct (pooled total is not a specialty) |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Mover Color | #14B8A6 | Non-blank, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | AZ Payment per Visit | (BLANK) | BLANK, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Outlier Count High | (BLANK) | BLANK, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Outlier Count Low | (BLANK) | BLANK, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Outlier Count Total | (BLANK) | BLANK, correct |
| T1 year 2021, no AZ provider data | `DimYear[yr] = 2021` | Providers in Scope | (BLANK) | BLANK, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | Spec Est Visits | 559 | Non-blank, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | 2019 Share | 0.6297 | Non-blank, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | 2024 Share | (BLANK) | BLANK, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | Change 2019-2024 (pts) | (BLANK) | BLANK, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | Top Mover Change (pts) | (BLANK) | BLANK, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | Mover Color | #14B8A6 | Non-blank, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | AZ Payment per Visit | 69.4002 | Non-blank, correct |
| T2 specialty Pathology (2019 rows only) | `DimSpecialty[specialty] = "Pathology"` | Outlier Count High | (BLANK) | BLANK, correct |
| T3 specialty Certified Clinical Nurse Specialist (226 visits in 2019, none at 99214/5) | `DimSpecialty[specialty] = "Certified Clinical Nurse Specialist"` | 2019 Share | 0 | Non-blank, correct |
| T3 specialty Certified Clinical Nurse Specialist (226 visits in 2019, none at 99214/5) | `DimSpecialty[specialty] = "Certified Clinical Nurse Specialist"` | 2024 Share | 1 | Non-blank, correct |
| T3 specialty Certified Clinical Nurse Specialist (226 visits in 2019, none at 99214/5) | `DimSpecialty[specialty] = "Certified Clinical Nurse Specialist"` | Change 2019-2024 (pts) | (BLANK) | BLANK, correct |
| T3 specialty Certified Clinical Nurse Specialist (226 visits in 2019, none at 99214/5) | `DimSpecialty[specialty] = "Certified Clinical Nurse Specialist"` | Outlier Count Total | (BLANK) | BLANK, correct |
| T4 specialty Geriatric Medicine (too small for outlier peer group) | `DimSpecialty[specialty] = "Geriatric Medicine"` | Change 2019-2024 (pts) | 14.4507 | Non-blank, correct |
| T4 specialty Geriatric Medicine (too small for outlier peer group) | `DimSpecialty[specialty] = "Geriatric Medicine"` | Outlier Count High | 0 | Non-blank, correct |
| T4 specialty Geriatric Medicine (too small for outlier peer group) | `DimSpecialty[specialty] = "Geriatric Medicine"` | Outlier Count Low | 0 | Non-blank, correct |
| T4 specialty Geriatric Medicine (too small for outlier peer group) | `DimSpecialty[specialty] = "Geriatric Medicine"` | Outlier Count Total | 0 | Non-blank, correct |
| T4 specialty Geriatric Medicine (too small for outlier peer group) | `DimSpecialty[specialty] = "Geriatric Medicine"` | Providers in Scope | 12 | Non-blank, correct |
| T5 specialty Psychiatry (control) | `DimSpecialty[specialty] = "Psychiatry"` | 2019 Share | 0.5982 | Non-blank, correct |
| T5 specialty Psychiatry (control) | `DimSpecialty[specialty] = "Psychiatry"` | 2024 Share | 0.7754 | Non-blank, correct |
| T5 specialty Psychiatry (control) | `DimSpecialty[specialty] = "Psychiatry"` | Change 2019-2024 (pts) | 17.7158 | Non-blank, correct |
| T5 specialty Psychiatry (control) | `DimSpecialty[specialty] = "Psychiatry"` | Top Mover Change (pts) | 17.7158 | Non-blank, correct |
| T6 year 2017 (first year, no prior year) | `DimYear[yr] = 2017` | Services YoY % | (BLANK) | BLANK, correct |
| T6 year 2017 (first year, no prior year) | `DimYear[yr] = 2017` | AZ Rank | 1 | Non-blank, correct |
| T7 all years (no single-year context) | `(none)` | Services YoY % | (BLANK) | BLANK, correct |
| T7 all years (no single-year context) | `(none)` | AZ Rank | (BLANK) | BLANK, correct |
| T7 all years (no single-year context) | `(none)` | States Ranked | (BLANK) | BLANK, correct |
| T7 all years (no single-year context) | `(none)` | AZ Established High Share | 0.59 | Non-blank, correct |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | Established 99214+99215 Share | 0.5424 | Non-blank, correct |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | New 99204+99205 Share | 0.5393 | Non-blank, correct |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | High-Level Share (All) | 0 | Non-blank, correct |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | Level Share within Patient Type | 0.0439 | Non-blank, correct (no patient-type filter in this context, so this is 99203 as a share of all visits) |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | AZ Established High Share | 0.59 | Non-blank, correct |
| T8 code filter 99203 (new-patient code only) | `DimEM[hcpcs_cd] = "99203"` | Established Services | (BLANK) | BLANK, correct |
| T9 patient type New slicer | `DimEM[patient_type] = "New"` | Established 99214+99215 Share | 0.5424 | Non-blank, correct |
| T9 patient type New slicer | `DimEM[patient_type] = "New"` | New 99204+99205 Share | 0.5393 | Non-blank, correct |
| T9 patient type New slicer | `DimEM[patient_type] = "New"` | Established Services | 1637973364.1 | Non-blank, correct |
| T9 patient type New slicer | `DimEM[patient_type] = "New"` | New Services | 208091005.5 | Non-blank, correct |
| T9 patient type New slicer | `DimEM[patient_type] = "New"` | Avg Payment per Visit | 95.9294 | Non-blank, correct |
| T10 patient type Established slicer | `DimEM[patient_type] = "Established"` | Established 99214+99215 Share | 0.5424 | Non-blank, correct |
| T10 patient type Established slicer | `DimEM[patient_type] = "Established"` | New 99204+99205 Share | 0.5393 | Non-blank, correct |
| T10 patient type Established slicer | `DimEM[patient_type] = "Established"` | New Services | 208091005.5 | Non-blank, correct |
| T11 territory under 50,000 established visits (Guam, 46,906) | `FactEM[geo_desc] = "Guam", DimYear[yr] = 2024` | State Est Visits | 46906 | Non-blank, correct |
| T11 territory under 50,000 established visits (Guam, 46,906) | `FactEM[geo_desc] = "Guam", DimYear[yr] = 2024` | State Est High Share | (BLANK) | BLANK, correct |
| T12 state Arizona 2024 | `FactEM[geo_desc] = "Arizona", DimYear[yr] = 2024` | State Est Visits | 4937511.1 | Non-blank, correct |
| T12 state Arizona 2024 | `FactEM[geo_desc] = "Arizona", DimYear[yr] = 2024` | State Est High Share | 0.6209 | Non-blank, correct |
| T12 state Arizona 2024 | `FactEM[geo_desc] = "Arizona", DimYear[yr] = 2024` | State Bar Color | #F59E0B | Non-blank, correct |
| T13 year with no data (2016, not in DimYear) | `FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )` | Total Services | (BLANK) | BLANK, correct |
| T13 year with no data (2016, not in DimYear) | `FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )` | Established 99214+99215 Share | (BLANK) | BLANK, correct |
| T13 year with no data (2016, not in DimYear) | `FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )` | AZ Gap vs National (pts) | (BLANK) | BLANK, correct |
| T13 year with no data (2016, not in DimYear) | `FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )` | AZ Rank | (BLANK) | BLANK, correct |
| T13 year with no data (2016, not in DimYear) | `FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )` | Services YoY % | (BLANK) | BLANK, correct |

T1b (year 2024, control) returned values for every measure: Spec Est Visits 4,833,988, Outlier High 71, Outlier Low 212, Providers in Scope 8,766.

## Pitfalls found and how they are handled

1. **BLANK compares as 0.** `BLANK() < 3` is TRUE. `Mover Color` and the volume gates use `NOT ISBLANK ( x ) && x < n`.
2. **BLANK numerator vs real zero.** First version returned BLANK for specialties with visits but no 99214/99215 (Certified Clinical Nurse Specialist 2019 is a real 0%). Fixed with `COALESCE ( numerator, 0 )` after the denominator guard.
3. **Code filter above 100%.** With a `99203` slicer, the first version of the share measures used an unfiltered numerator over a filtered denominator. Denominators now `REMOVEFILTERS` the code columns (test T8: shares stay 54.24% and 53.93%).
4. **Fixed-year measures.** `2019 Share`, `2024 Share` and `Change` override the year filter on purpose. In a 2021 context they still return 2019 and 2024 values (test T1). Visuals that use them do not use a year axis.
5. **Pooled rank is misleading.** `AZ Rank` over all years returned 1 of 55 (territories pooled). It now returns BLANK unless exactly one year is in context (T7).
6. **Small states and territories.** `State Est High Share` is BLANK under 50,000 established visits (Guam 46,906, Virgin Islands 34,804, Northern Mariana Islands 2,911, Armed Forces and Unknown rows). Same cutoff as `sql/04`.
7. **National vs state rows.** `v_em_fact` holds national and state rows. Every volume measure filters `geo_level` explicitly, otherwise totals double count.
8. **Provider privacy.** The model imports only aggregate views. Outlier counts come from `v_outlier_counts` (counts per specialty and year). No provider id or provider-level row is imported or shown.
9. **Chart-label units.** Custom-format scaling (`#,0.0,,"M"`) rendered as raw digits in labels, so `Total Services (M)` divides by 1,000,000 in DAX instead.
10. **Outliers are statistical variance** (z > 2 or z < -2 within specialty and year, 100+ established visits, 10+ peers), not evidence of fraud or upcoding.
