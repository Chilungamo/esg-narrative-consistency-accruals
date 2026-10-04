# ESG Narrative Consistency and Discretionary Accruals

**Author:** Albert Limani — Pace University, ACC 692Q
**Advisor:** Professor Sen Kaustav

## Overview

This repository contains the full empirical pipeline for a research project examining
whether **consistency in ESG-related language across sections of 10-K filings** (the
"ESG Narrative Consistency Index," or **ENCI**) is associated with **financial reporting
quality**, proxied by discretionary accruals from the modified Jones model.

**Sample:** S&P 500 constituents (non-financial, non-utility).
Accruals are computed for fiscal years 1994–2024. **ENCI is defined only for fiscal
years ending on or after 1 December 2005**, when Item 1A (Risk Factors) became a
required 10-K section; ENCI regressions therefore cover FY2005/06–2024.

**Data sources:** WRDS (Compustat Fundamentals Annual, CRSP, CRSP/Compustat Merged,
SEC Analytics Suite full-text filings)

> **The published dashboard (`index.html`) is built from synthetic data** and is
> watermarked as such. It demonstrates the visualization layer only; it is not an
> empirical result.

## Research Questions

1. Do firms whose ESG language is *consistent* between the MD&A and Risk Factor
   sections of their 10-K (high ENCI) exhibit lower absolute discretionary accruals?
2. Does the strength of that relationship depend on overall ESG disclosure intensity?

## Repository Structure

```
esg-narrative-consistency-accruals/
├── README.md
├── requirements.txt
├── index.html                          # GitHub Pages copy of the dashboard (synthetic)
├── sas/
│   ├── run_all.sas                     # Driver: runs 00 → 05 in one session
│   ├── 00_setup_libraries.sas          # Parameters, WRDS libraries, %winsorize, %assert_unique
│   ├── 01_sp500_universe.sas           # Full Compustat universe + CCM link + S&P 500 flag
│   ├── 02_modified_jones_dac.sas       # Modified Jones DA (full universe) + KLW performance matching
│   ├── 03_esg_text_intensity.sas       # 10-K ↔ FYE matching, regex ESG word counts
│   ├── 04_enci_construction.sas        # ENCI, pillar ENCI, temporal ENCI, ESG intensity
│   └── 05_regression_models.sas        # FE regressions, firm-clustered SEs (PROC SURVEYREG)
├── python/
│   ├── generate_sample_data.py         # Synthetic panel for demo / dev (no WRDS needed)
│   ├── data_pipeline.py                # Load + clean SAS export (panel + coefficient table)
│   └── visualize.py                    # Builds the interactive HTML dashboard
├── data/
│   └── (SAS .xlsx exports land here — gitignored)
├── outputs/
│   └── enci_dashboard.html             # Interactive Plotly dashboard (generated)
└── docs/
    └── variable_definitions.md
```

## Pipeline

### 1. SAS layer (runs on WRDS SAS Studio)

Edit the parameters at the top of `00_setup_libraries.sas` (paths, sample years) and
**verify the source-table names** with the diagnostics block in that file — in
particular the GVKEY–CIK link table and the MD&A / Risk Factor text tables, whose
names and column names are parameters (`&cik_link_tbl`, `&mda_tbl`, `&rf_tbl`, …).
Then set `code_path` in `run_all.sas` and run it:

```sas
%include "/home/youruser/esg_accruals/sas/run_all.sas";
```

All steps share one WORK library, so run them in a single session. Each join is
followed by `%assert_unique`, which writes an `ERROR:` line to the log if a key is
duplicated.

Design notes:

- **Jones model on the full universe.** Total accruals and the cross-sectional
  modified Jones regressions (with intercept) are estimated on all non-financial,
  non-utility Compustat firms by SIC2 × fiscal year (≥ 10 obs per cell); S&P 500
  members are selected afterwards.
- **Total accruals** use the cash-flow approach, `TA = [IB − (OANCF − XIDOC)] / AT(t−1)`
  (Hribar & Collins 2002).
- **Lags** require the immediately preceding fiscal year; gaps leave lags missing.
- **Performance matching** follows Kothari, Leone & Wasley (2005): each firm-year is
  matched to the other firm in its SIC2-year with the closest ROA.
- **Text alignment.** Each firm-year is matched to the first 10-K filed within 365
  days after fiscal year-end; MD&A and Risk Factor text come from the same filing.
- **Inference.** Firm and year fixed effects, standard errors clustered by firm.

`05_regression_models.sas` writes `ESG_DA_panel.xlsx` with sheets `MainPanel`,
`JonesCoefficients`, and `Coefficients` (regression estimates for H1, H2, the E/S/G
models, and the performance-matched robustness model).

### 2. Python layer (runs locally, for visualization & portfolio)

```bash
pip install -r requirements.txt

# Option A: real SAS output (also extracts the Coefficients sheet)
python python/data_pipeline.py --input data/ESG_DA_panel.xlsx
python python/visualize.py --input data/panel_clean.csv

# Option B: no WRDS access -- synthetic panel (dashboard is watermarked)
python python/generate_sample_data.py
python python/data_pipeline.py --input data/sample_panel.csv
python python/visualize.py --input data/panel_clean.csv
```

This produces `outputs/enci_dashboard.html`, a single interactive file. Copy it to
`index.html` to update the GitHub Pages site.

## Dashboard

`python/visualize.py` renders four linked panels:

1. **ENCI vs. |Discretionary Accruals| scatter** with a pooled OLS line (descriptive),
   colored by ESG disclosure intensity.
2. **ESG intensity by section over time** — MD&A vs. Risk Factors, with the Item 1A
   start marked.
3. **ENCI coefficient plot** (overall and E / S / G) with 95% confidence intervals from
   the firm + year fixed-effects models with firm-clustered SEs. Uses the SAS
   `Coefficients` sheet when available; otherwise re-estimates the same specification
   in statsmodels.
4. **Interaction heatmap** — ESG intensity quintile × ENCI quintile, mean |DAC| (H2).

Any dashboard built from `generate_sample_data.py` output is labeled
**SYNTHETIC DEMO DATA**.

## Citation

If referencing the methodology, please cite the underlying models:

- Jones, J. J. (1991). Earnings Management During Import Relief Investigations.
  *Journal of Accounting Research*, 29(2), 193–228.
- Dechow, P. M., Sloan, R. G., & Sweeney, A. P. (1995). Detecting Earnings Management.
  *The Accounting Review*, 70(2), 193–225.
- Hribar, P., & Collins, D. W. (2002). Errors in Estimating Accruals: Implications for
  Empirical Research. *Journal of Accounting Research*, 40(1), 105–134.
- Kothari, S. P., Leone, A. J., & Wasley, C. E. (2005). Performance Matched
  Discretionary Accrual Measures. *Journal of Accounting and Economics*, 39(1), 163–197.
- Baier, P., Berninger, M., & Kiesel, F. (2020). Environmental, Social and Governance
  Reporting in Annual Reports: A Textual Analysis. *Financial Markets, Institutions &
  Instruments*, 29(3), 93–118.

## License

MIT License — see `LICENSE`.
