"""
data_pipeline.py

Loads the analysis panel exported by 05_regression_models.sas
(ESG_DA_panel.xlsx, sheet "MainPanel") -- or a synthetic CSV from
generate_sample_data.py -- normalizes column names to the schema used by
visualize.py, and writes a clean CSV. If the workbook has a "Coefficients"
sheet (firm/year-FE, firm-clustered estimates from PROC SURVEYREG), it is
written alongside so the dashboard plots the paper's estimates rather than
re-estimating them.

Usage:
    python python/data_pipeline.py --input data/ESG_DA_panel.xlsx
    python python/data_pipeline.py --input data/sample_panel.csv
"""

import argparse
import os

import pandas as pd

REQUIRED_COLS = [
    "gvkey", "fyear", "ABS_DAC", "ABS_PM_DAC",
    "ENCI", "ENCI_env", "ENCI_soc", "ENCI_gov",
    "ESG_INTENSITY", "esg_int_mda", "esg_int_rf",
    "SIZE", "LEVERAGE", "MTB", "ROA",
]
COEF_COLS = ["model", "dv", "Parameter", "Estimate", "StdErr", "LowerCL", "UpperCL"]


def normalize_columns(df: pd.DataFrame, canonical: list) -> pd.DataFrame:
    """Strip whitespace and map case-insensitive matches onto canonical names."""
    df = df.rename(columns=lambda c: str(c).strip())
    lookup = {c.lower(): c for c in canonical}
    return df.rename(columns=lambda c: lookup.get(c.lower(), c))


def load_panel(path: str) -> pd.DataFrame:
    if path.lower().endswith((".xlsx", ".xls")):
        df = pd.read_excel(path, sheet_name="MainPanel")
    else:
        df = pd.read_csv(path)

    df = normalize_columns(df, REQUIRED_COLS + ["data_source"])

    missing = [c for c in REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(
            f"Input file is missing required columns: {missing}. "
            "Check the SAS export or regenerate sample data with "
            "generate_sample_data.py."
        )

    if "data_source" not in df.columns:
        df["data_source"] = "wrds"

    # Keep every firm-year with an accrual measure. ENCI is legitimately
    # missing before Item 1A (FYE < Dec 2005); each dashboard panel drops
    # the rows it cannot use, so the MD&A trend keeps its pre-2005 years.
    return df.dropna(subset=["ABS_DAC"])


def load_coefficients(path: str):
    """Return the SAS Coefficients sheet, or None if it is absent."""
    if not path.lower().endswith((".xlsx", ".xls")):
        return None
    try:
        coefs = pd.read_excel(path, sheet_name="Coefficients")
    except ValueError:            # sheet not present
        return None
    return normalize_columns(coefs, COEF_COLS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean and standardize the ESG/DAC panel")
    parser.add_argument("--input", type=str, required=True,
                        help="Path to ESG_DA_panel.xlsx or sample_panel.csv")
    parser.add_argument("--out", type=str, default="data/panel_clean.csv")
    parser.add_argument("--coefs-out", type=str, default="data/coefficients.csv")
    args = parser.parse_args()

    panel = load_panel(args.input)
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    panel.to_csv(args.out, index=False)
    print(f"Cleaned panel written to {args.out} ({len(panel):,} rows)")

    coefs = load_coefficients(args.input)
    if coefs is not None:
        coefs.to_csv(args.coefs_out, index=False)
        print(f"SAS coefficient table written to {args.coefs_out} ({len(coefs)} rows)")
