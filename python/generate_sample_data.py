"""
generate_sample_data.py

Generates a SYNTHETIC firm-year panel with the same schema as the SAS
export, so the visualization layer can be developed and demoed without
WRDS access.

The data are NOT real and must never be cited as empirical evidence. Every
row carries data_source = "synthetic", and visualize.py watermarks any
dashboard built from it.

Structural features mirrored from the real pipeline:
  * Risk Factor (Item 1A) intensities exist only for fiscal years >= 2005
    (Item 1A mandatory for FYE on or after 1 Dec 2005; assumes Dec FYE),
    so ENCI and ESG_INTENSITY are missing before that.
  * Pillar ENCI is built from pillar-level intensities, so it is <= 0 by
    construction, exactly like the overall ENCI.

Usage:
    python generate_sample_data.py [--n-firms 500] [--out data/sample_panel.csv]
"""

import argparse
import os

import numpy as np
import pandas as pd

RF_FIRST_FYEAR = 2005
PILLARS = {"env": 0.40, "soc": 0.35, "gov": 0.25}   # rough E/S/G word shares


def zscore_by_year(df: pd.DataFrame, col: str) -> pd.Series:
    """Within-fiscal-year standardization; sample SD, as PROC STDIZE METHOD=STD (VARDEF=DF)."""
    g = df.groupby("fyear")[col]
    return (df[col] - g.transform("mean")) / g.transform("std")


def winsorize_by_year(df: pd.DataFrame, col: str, pct: float = 0.01) -> pd.Series:
    """Clip at the pct / 1-pct quantiles within fiscal year; NaN stays NaN."""
    g = df.groupby("fyear")[col]
    return df[col].clip(g.transform(lambda s: s.quantile(pct)),
                        g.transform(lambda s: s.quantile(1 - pct)))


def generate_panel(n_firms: int = 500, start_yr: int = 1994, end_yr: int = 2024,
                   seed: int = 42) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    years = np.arange(start_yr, end_yr + 1)
    sic2_codes = [10, 13, 20, 28, 35, 36, 37, 50, 51, 73, 80, 99]

    rows = []
    for gvkey in range(1, n_firms + 1):
        sic2 = int(rng.choice(sic2_codes))
        size_base = rng.normal(8.9, 1.3)                       # log(total assets)
        leverage_base = np.clip(rng.normal(0.53, 0.18), 0.05, 1.2)
        firm_quality = rng.normal(0, 1)                        # latent governance factor

        for fyear in years:
            year_trend = (fyear - start_yr) / (end_yr - start_yr)
            # Firms with high latent quality keep MD&A and RF closer together
            divergence = rng.normal(0.4, 0.25) * (1 - 0.4 * firm_quality)

            row = {"gvkey": gvkey, "fyear": int(fyear), "SIC2": sic2}
            for pillar, share in PILLARS.items():
                mda = max(share * (0.005 + 0.035 * year_trend + 0.01 * firm_quality)
                          + rng.normal(0, 0.003), 0.0)
                rf = max(mda * (1 - 0.25 * divergence) + rng.normal(0, 0.001), 0.0)
                row[f"{pillar}_int_mda"] = mda
                row[f"{pillar}_int_rf"] = rf if fyear >= RF_FIRST_FYEAR else np.nan

            roa = np.clip(rng.normal(0.05, 0.06), -0.3, 0.4)
            size = size_base + 0.02 * (fyear - start_yr) + rng.normal(0, 0.05)
            leverage = np.clip(leverage_base + rng.normal(0, 0.03), 0.02, 1.5)
            mtb = np.clip(rng.lognormal(mean=0.9, sigma=0.5), 0.3, 25)

            # Signed DA; magnitude falls with latent quality and consistency
            dac = (0.02 - 0.01 * firm_quality + 0.02 * leverage
                   - 0.006 * (size - 8.9) - 0.05 * roa
                   - 0.04 * (1 - divergence) + rng.normal(0, 0.05))
            pm_dac = dac + rng.normal(0, 0.01)

            row.update({
                "DAC": dac, "ABS_DAC": abs(dac),
                "PM_DAC": pm_dac, "ABS_PM_DAC": abs(pm_dac),
                "SIZE": size, "LEVERAGE": leverage, "MTB": mtb, "ROA": roa,
            })
            rows.append(row)

    df = pd.DataFrame(rows)

    # Section totals = sum of pillars (NaN propagates for pre-Item 1A RF)
    for sec in ("mda", "rf"):
        df[f"esg_int_{sec}"] = df[[f"{p}_int_{sec}" for p in PILLARS]].sum(axis=1, min_count=3)

    df["ESG_INTENSITY"] = (df["esg_int_mda"] + df["esg_int_rf"]) / 2

    # ENCI and pillar ENCI from within-year Z-scores, as in 04_enci_construction.sas
    for prefix in ["esg"] + list(PILLARS):
        z_mda = zscore_by_year(df, f"{prefix}_int_mda")
        z_rf = zscore_by_year(df, f"{prefix}_int_rf")
        enci_col = "ENCI" if prefix == "esg" else f"ENCI_{prefix}"
        df[enci_col] = -(z_mda - z_rf).abs()
        if prefix == "esg":
            df["Z_esg_mda"], df["Z_esg_rf"] = z_mda, z_rf

    for col in ["ABS_DAC", "ABS_PM_DAC", "ENCI", "ENCI_env", "ENCI_soc", "ENCI_gov",
                "ESG_INTENSITY", "LEVERAGE", "MTB"]:
        df[col] = winsorize_by_year(df, col)

    df["ESG_x_ENCI"] = df["ESG_INTENSITY"] * df["ENCI"]
    df["data_source"] = "synthetic"
    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate synthetic ESG/DAC panel")
    parser.add_argument("--n-firms", type=int, default=500)
    parser.add_argument("--start-yr", type=int, default=1994)
    parser.add_argument("--end-yr", type=int, default=2024)
    parser.add_argument("--out", type=str, default="data/sample_panel.csv")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    panel = generate_panel(args.n_firms, args.start_yr, args.end_yr, args.seed)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    panel.to_csv(args.out, index=False)
    print(f"Wrote {len(panel):,} SYNTHETIC rows to {args.out}")
    print(panel.describe().T[["count", "mean", "std", "min", "max"]])
