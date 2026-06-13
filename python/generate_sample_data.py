"""
generate_sample_data.py

Generates a synthetic firm-year panel that mimics the structure and
correlations described in the research paper, so the visualization
layer (and any downstream analysis code) can be developed and demoed
without WRDS access.

The synthetic data is NOT real and should never be cited as empirical
evidence -- it exists purely to make the repository runnable end-to-end
for portfolio / demo purposes.

Usage:
    python generate_sample_data.py [--n-firms 500] [--out data/sample_panel.csv]
"""

import argparse
import numpy as np
import pandas as pd


def generate_panel(n_firms: int = 500, start_yr: int = 1994, end_yr: int = 2024,
                    seed: int = 42) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    years = np.arange(start_yr, end_yr + 1)
    sic2_codes = [10, 13, 20, 28, 35, 36, 37, 50, 51, 73, 80, 99]

    rows = []
    for gvkey in range(1, n_firms + 1):
        sic2 = int(rng.choice(sic2_codes))
        size_base = rng.normal(8.9, 1.3)          # log(total assets)
        leverage_base = np.clip(rng.normal(0.53, 0.18), 0.05, 1.2)
        firm_quality = rng.normal(0, 1)            # latent "good governance" factor

        for fyear in years:
            # ESG intensity rises secularly over the sample, with noise
            year_trend = (fyear - start_yr) / (end_yr - start_yr)
            esg_int_mda = np.clip(
                0.005 + 0.035 * year_trend + rng.normal(0, 0.008)
                + 0.01 * firm_quality, 0, None
            )
            # RF tends to run a bit lower than MDA, but firms with high
            # "quality" keep the two sections closer together (consistency)
            divergence = rng.normal(0.4, 0.25) * (1 - 0.4 * firm_quality)
            esg_int_rf = np.clip(esg_int_mda * (1 - 0.25 * divergence), 0, None)

            # Sub-pillar splits (rough proportions E/S/G)
            for pillar, share in zip(["env", "soc", "gov"], [0.4, 0.35, 0.25]):
                pass  # sub-pillars derived later from totals for simplicity

            roa = np.clip(rng.normal(0.05, 0.06), -0.3, 0.4)
            size = size_base + 0.02 * (fyear - start_yr) + rng.normal(0, 0.05)
            leverage = np.clip(leverage_base + rng.normal(0, 0.03), 0.02, 1.5)
            mtb = np.clip(rng.lognormal(mean=0.9, sigma=0.5), 0.3, 25)

            # Discretionary accruals: lower when firm_quality high and ESG
            # sections are consistent; higher with leverage, lower with size
            base_noise = rng.normal(0, 0.05)
            consistency_effect = -0.04 * (1 - divergence)  # more consistent -> lower |DAC|
            dac = (
                0.02
                - 0.01 * firm_quality
                + 0.02 * leverage
                - 0.006 * (size - 8.9)
                - 0.05 * roa
                + consistency_effect
                + base_noise
            )
            pm_dac = dac + rng.normal(0, 0.01)

            rows.append({
                "gvkey": gvkey,
                "fyear": int(fyear),
                "SIC2": sic2,
                "DAC": dac,
                "ABS_DAC": abs(dac),
                "PM_DAC": pm_dac,
                "ABS_PM_DAC": abs(pm_dac),
                "esg_int_mda": esg_int_mda,
                "esg_int_rf": esg_int_rf,
                "ESG_INTENSITY": (esg_int_mda + esg_int_rf) / 2,
                "SIZE": size,
                "LEVERAGE": leverage,
                "MTB": mtb,
                "ROA": roa,
            })

    df = pd.DataFrame(rows)

    # --- Standardize ESG intensities within year, then compute ENCI ---
    for col, zcol in [("esg_int_mda", "Z_esg_mda"), ("esg_int_rf", "Z_esg_rf")]:
        df[zcol] = df.groupby("fyear")[col].transform(
            lambda x: (x - x.mean()) / x.std(ddof=0)
        )

    df["ENCI"] = -np.abs(df["Z_esg_mda"] - df["Z_esg_rf"])

    # Sub-pillar ENCI: derive correlated-but-distinct versions of ENCI
    rng2 = np.random.default_rng(seed + 1)
    for pillar in ["env", "soc", "gov"]:
        noise = rng2.normal(0, 0.15, size=len(df))
        df[f"ENCI_{pillar}"] = df["ENCI"] + noise

    # Winsorize key continuous variables at 1/99 by year
    def winsorize(group, col):
        lo, hi = group[col].quantile([0.01, 0.99])
        return group[col].clip(lo, hi)

    for col in ["ABS_DAC", "ABS_PM_DAC", "ENCI", "ESG_INTENSITY",
                "LEVERAGE", "MTB", "ENCI_env", "ENCI_soc", "ENCI_gov"]:
        df[col] = df.groupby("fyear", group_keys=False).apply(
            lambda g: winsorize(g, col)
        )

    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate synthetic ESG/DAC panel")
    parser.add_argument("--n-firms", type=int, default=500)
    parser.add_argument("--start-yr", type=int, default=1994)
    parser.add_argument("--end-yr", type=int, default=2024)
    parser.add_argument("--out", type=str, default="data/sample_panel.csv")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    panel = generate_panel(
        n_firms=args.n_firms,
        start_yr=args.start_yr,
        end_yr=args.end_yr,
        seed=args.seed,
    )

    import os
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    panel.to_csv(args.out, index=False)
    print(f"Wrote {len(panel):,} rows to {args.out}")
    print(panel.describe().T[["mean", "std", "min", "max"]])
