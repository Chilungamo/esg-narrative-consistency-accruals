# ESG Narrative Consistency and Discretionary Accruals

**Author:** Albert Limani — Pace University, ACC 692Q
**Advisor:** Professor Sen Kaustav

## Overview

This repository contains the full empirical pipeline for a research project examining
whether **consistency in ESG-related language across sections of 10-K filings** (the
"ESG Narrative Consistency Index," or **ENCI**) is associated with **financial reporting
quality**, proxied by discretionary accruals from the modified Jones model.

**Sample:** S&P 500 constituents, fiscal years 1994–2024
**Data sources:** WRDS (Compustat Fundamentals Annual, CRSP, CRSP/Compustat Merged,
SEC Analytics Suite full-text filings)

## Research Questions

1. Do firms whose ESG language is *consistent* between the MD&A and Risk Factor
   sections of their 10-K (high ENCI) exhibit lower absolute discretionary accruals?
2. Does the strength of that relationship depend on overall ESG disclosure intensity?

## Repository Structure

```
esg-accruals-repo/
├── README.md
├── requirements.txt
├── sas/
│   ├── 00_setup_libraries.sas          # WRDS libname declarations + diagnostics
│   ├── 01_sp500_universe.sas           # S&P 500 panel via Compustat + CCM + CRSP
│   ├── 02_modified_jones_dac.sas       # Modified Jones / performance-matched DAC
│   ├── 03_esg_text_intensity.sas       # PRXPARSE bag-of-words ESG intensity
│   ├── 04_enci_construction.sas        # ENCI + sub-pillar + temporal measures
│   └── 05_regression_models.sas        # Final panel regressions (PROC GLM)
├── python/
│   ├── generate_sample_data.py         # Synthetic panel for demo / dev (no WRDS needed)
│   ├── data_pipeline.py                # Load + clean SAS exports for analysis
│   └── visualize.py                    # Builds the interactive HTML dashboard
├── data/
│   └── (SAS .xlsx exports land here — gitignored)
├── outputs/
│   └── enci_dashboard.html             # Interactive Plotly dashboard (generated)
└── docs/
    ├── research_proposal.md
    └── variable_definitions.md
```

## Pipeline

The pipeline is split into two layers:

### 1. SAS layer (runs on WRDS SAS Studio)
Run scripts `00` → `05` in order. Each script reads the prior step's output dataset
and writes the next one. The final step (`05_regression_models.sas`) exports
`ESG_DA_panel.xlsx` containing the analysis panel and Jones model coefficients.

```sas
%include "00_setup_libraries.sas";
%include "01_sp500_universe.sas";
%include "02_modified_jones_dac.sas";
%include "03_esg_text_intensity.sas";
%include "04_enci_construction.sas";
%include "05_regression_models.sas";
```

### 2. Python layer (runs locally, for visualization & portfolio)
Since SAS output isn't great for interactive presentation, the Python layer turns
the exported panel into a portfolio-ready interactive dashboard.

```bash
pip install -r requirements.txt

# Option A: use real SAS output
python python/data_pipeline.py --input data/ESG_DA_panel.xlsx

# Option B: no WRDS access? generate a realistic synthetic panel
python python/generate_sample_data.py

# Build the dashboard (works on either real or synthetic data)
python python/visualize.py
```

This produces `outputs/enci_dashboard.html` — a single self-contained interactive
file you can open in any browser or embed in a portfolio site / GitHub Pages.

## Suggested Visualization (Portfolio Showcase)

The dashboard (`python/visualize.py`) renders four linked panels:

1. **ENCI vs. |Discretionary Accruals| scatter** with an OLS trendline and points
   colored by ESG disclosure intensity — the core empirical result (H1) at a glance.
2. **ESG intensity trends, 1994–2024** — separate lines for MD&A vs. Risk Factor
   sections, showing the secular rise in ESG language and the MD&A/RF gap that
   motivates ENCI.
3. **Sub-pillar coefficient plot** (E / S / G) — bar chart of each pillar's ENCI
   coefficient from `05_regression_models.sas`, with confidence intervals.
4. **Interaction heatmap** — binned ESG intensity (rows) × ENCI (columns) showing
   mean |DAC| in each cell, visually demonstrating the H2 interaction effect.

This combination is deliberately chosen because it tells the paper's story in one
scrollable page: descriptive trend → main result → mechanism (sub-pillars) →
interaction effect — without requiring the viewer to read the regression tables.

## Citation

If referencing the methodology, please cite the underlying models:

- Jones, J. J. (1991). Earnings Management During Import Relief Investigations.
  *Journal of Accounting Research*, 29(2), 193–228.
- Kothari, S. P., Leone, A. J., & Wasley, C. E. (2005). Performance Matched
  Discretionary Accrual Measures. *Journal of Accounting and Economics*, 39(1), 163–197.
- Baier, P., Berninger, M., & Kiesel, F. (2020). Environmental, Social and Governance
  Reporting in Annual Reports: A Textual Analysis. *Financial Markets, Institutions &
  Instruments*, 29(3), 93–118.

## License

MIT License — see `LICENSE`.
