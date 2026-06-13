"""
data_pipeline.py

Loads the analysis panel exported from SAS (ESG_DA_panel.xlsx, sheet
"MainPanel") and applies light cleaning so it matches the schema expected
by visualize.py. If a real SAS export isn't available, falls back to the
synthetic panel produced by generate_sample_data.py.

Usage:
    python data_pipeline.py --input data/ESG_DA_panel.xlsx --out data/panel_clean.csv
    python data_pipeline.py --input data/sample_panel.csv  --out data/panel_clean.csv
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


def load_panel(path: str) -> pd.DataFrame:
    if path.lower().endswith((".xlsx", ".xls")):
        df = pd.read_excel(path, sheet_name="MainPanel")
    else:
        df = pd.read_csv(path)

    # Normalize column names (SAS sometimes returns different cases)
    df.columns = [c.strip() for c in df.columns]

    missing = [c for c in REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(
            f"Input file is missing required columns: {missing}. "
            "Check the SAS export or regenerate sample data with "
            "generate_sample_data.py."
        )

    # Drop rows with missing key variables
    df = df.dropna(subset=["ABS_DAC", "ENCI", "ESG_INTENSITY"])

    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean and standardize the ESG/DAC panel")
    parser.add_argument("--input", type=str, required=True,
                         help="Path to ESG_DA_panel.xlsx or sample_panel.csv")
    parser.add_argument("--out", type=str, default="data/panel_clean.csv")
    args = parser.parse_args()

    panel = load_panel(args.input)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    panel.to_csv(args.out, index=False)
    print(f"Cleaned panel written to {args.out} ({len(panel):,} rows)")
