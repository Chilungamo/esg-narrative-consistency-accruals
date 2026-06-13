# Variable Definitions

| Variable | Definition |
|---|---|
| `gvkey` | Compustat firm identifier |
| `fyear` | Fiscal year |
| `SIC2` | Two-digit SIC industry code (from `sich` in Compustat) |
| `DAC` | Discretionary accruals — residual from the cross-sectional modified Jones model, estimated by SIC2 × fiscal year |
| `ABS_DAC` | `\|DAC\|`, absolute value of discretionary accruals |
| `PM_DAC` | Performance-matched discretionary accruals (Kothari, Leone & Wasley, 2005): `DAC` minus the median `DAC` of firms in the same SIC2, fiscal year, and ROA decile |
| `ABS_PM_DAC` | `\|PM_DAC\|` |
| `esg_int_mda` | ESG word count / total word count in the MD&A section of the 10-K |
| `esg_int_rf` | ESG word count / total word count in the Risk Factors section of the 10-K |
| `ESG_INTENSITY` | Average of `esg_int_mda` and `esg_int_rf` |
| `Z_esg_mda`, `Z_esg_rf` | `esg_int_mda` / `esg_int_rf` standardized to mean 0, sd 1 within fiscal year |
| `ENCI` | ESG Narrative Consistency Index = `-\|Z_esg_mda - Z_esg_rf\|`. Closer to 0 = more consistent narrative across sections |
| `ENCI_env`, `ENCI_soc`, `ENCI_gov` | Pillar-specific ENCI using Environmental / Social / Governance word counts only |
| `ENCI_t_mda`, `ENCI_t_rf` | Temporal ENCI: `-\|Z_t - Z_{t-1}\|` within section, capturing year-over-year stability |
| `ESG_x_ENCI` | Interaction term `ESG_INTENSITY * ENCI` |
| `SIZE` | `log(AT)`, natural log of total assets |
| `LEVERAGE` | `LT / AT`, total liabilities over total assets |
| `ROA` | `IB / ((AT_t + AT_{t-1}) / 2)`, return on average assets |
| `MTB` | `MKVALT / CEQ`, market-to-book ratio |

All continuous variables (`ABS_DAC`, `ABS_PM_DAC`, `ENCI`, `ENCI_env/soc/gov`,
`ESG_INTENSITY`, `LEVERAGE`, `MTB`) are winsorized at the 1st and 99th
percentiles within each fiscal year.
