# Variable Definitions

| Variable | Definition |
|---|---|
| `gvkey` | Compustat firm identifier |
| `fyear` | Compustat fiscal year |
| `sic_final` | Historical SIC (`sich`); `comp.company.sic` when `sich` is missing |
| `SIC2` | Two-digit SIC, `int(sic_final / 100)`. SIC 49 and 60–69 excluded |
| `sp500` | 1 if the firm is an S&P 500 constituent at fiscal year-end: CRSP `msp500list` via CCM LU/LC link when CRSP is licensed, otherwise Compustat `idxcst_his` (`gvkeyx = '000003'`) matched on GVKEY |
| `TA` | Total accruals, cash-flow approach: `[IB − (OANCF − XIDOC)] / AT(t−1)` |
| `DAC` | Discretionary accruals — residual of the cross-sectional modified Jones model `TA = a + b1·(1/AT(t−1)) + b2·(ΔSALE − ΔRECT)/AT(t−1) + b3·PPEGT/AT(t−1)`, estimated by SIC2 × fyear on the full non-financial Compustat universe (≥ 10 obs per cell) |
| `NDAC` | Fitted (non-discretionary) accruals from the same model |
| `ABS_DAC` | `\|DAC\|` |
| `PM_DAC` | Performance-matched DA (Kothari, Leone & Wasley, 2005): `DAC` minus the `DAC` of the other firm in the same SIC2-year with the closest current-year `ROA` |
| `ABS_PM_DAC` | `\|PM_DAC\|` |
| `words_mda`, `words_rf` | Total words in the MD&A / Risk Factors section of the matched 10-K |
| `esg_int_mda` | ESG dictionary matches / total words, MD&A section |
| `esg_int_rf` | ESG dictionary matches / total words, Risk Factors section. Missing for FYE before 1 Dec 2005 (Item 1A not required) |
| `env_int_*`, `soc_int_*`, `gov_int_*` | Pillar-specific intensities, same construction |
| `ESG_INTENSITY` | Average of raw `esg_int_mda` and `esg_int_rf` |
| `Z_esg_mda`, `Z_esg_rf` | `esg_int_mda` / `esg_int_rf` standardized to mean 0, sd 1 within fiscal year |
| `ENCI` | ESG Narrative Consistency Index = `-\|Z_esg_mda − Z_esg_rf\|`. ≤ 0; closer to 0 = more consistent narrative across sections |
| `ENCI_env`, `ENCI_soc`, `ENCI_gov` | Pillar-specific ENCI using Environmental / Social / Governance counts only |
| `ENCI_t_mda`, `ENCI_t_rf` | Temporal ENCI: `-\|Z_t − Z_{t−1}\|` within section; requires the immediately preceding fiscal year |
| `ESG_x_ENCI` | Interaction term `ESG_INTENSITY × ENCI` (computed after winsorizing both) |
| `SIZE` | `log(AT)` |
| `LEVERAGE` | `LT / AT` |
| `ROA` | `IB / ((AT_t + AT_{t−1}) / 2)` |
| `MTB` | `(PRCC_F × CSHO) / CEQ` (`MKVALT` if price or shares missing); `CEQ > 0` |

**Matching filings to fiscal years.** Each gvkey–datadate is matched to the first
original 10-K (`10-K`, `10-K405`, `10-KT`) filed within 365 days after `datadate`;
MD&A and Risk Factors come from that filing.

**Winsorization.** Jones-model inputs (`TA`, ΔREV term, PP&E term, `1/AT(t−1)`, `ROA`)
are winsorized at 1/99 within fiscal year on the full universe before estimation.
In the analysis panel, `ABS_DAC`, `ABS_PM_DAC`, `ENCI`, `ENCI_env/soc/gov`,
`ESG_INTENSITY`, `LEVERAGE`, and `MTB` are winsorized at 1/99 within fiscal year.
Missing values are left missing.

**Regressions.** `PROC SURVEYREG` with firm and year fixed effects (`class gvkey fyear`)
and standard errors clustered by firm (`cluster gvkey`).
