"""
visualize.py

Builds a single self-contained interactive HTML dashboard for the ESG
Narrative Consistency / Discretionary Accruals study:

  1. ENCI vs |DAC| scatter (H1), colored by ESG intensity, pooled OLS line
  2. ESG intensity trends by section (MD&A vs Risk Factors)
  3. ENCI coefficients on |DAC| (overall + E/S/G) with 95% CIs, from the
     firm + year fixed-effects models with firm-clustered SEs
  4. ESG intensity x ENCI quintile heatmap of mean |DAC| (H2)

Panel 3 uses the SAS coefficient table (data/coefficients.csv, written by
data_pipeline.py from the "Coefficients" sheet) when available, so the
dashboard shows the paper's estimates. Otherwise it re-estimates the same
specification in statsmodels.

Any panel with data_source == "synthetic" is watermarked as demo data.

Usage:
    python python/visualize.py --input data/panel_clean.csv --out outputs/enci_dashboard.html
"""

import argparse
import os

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import statsmodels.formula.api as smf

CONTROLS = ["SIZE", "LEVERAGE", "MTB", "ROA"]
PILLARS = {           # label -> (ENCI column, SAS model tag)
    "Overall": ("ENCI", "H1"),
    "Environmental": ("ENCI_env", "ENV"),
    "Social": ("ENCI_soc", "SOC"),
    "Governance": ("ENCI_gov", "GOV"),
}
ITEM_1A_FYEAR = 2005


def fe_coefficient(df: pd.DataFrame, x: str) -> dict:
    """|DAC| on x + controls with firm and year FE; SEs clustered by firm."""
    sub = df.dropna(subset=["ABS_DAC", x] + CONTROLS)
    formula = f"ABS_DAC ~ {x} + {' + '.join(CONTROLS)} + C(gvkey) + C(fyear)"
    res = smf.ols(formula, data=sub).fit(
        cov_type="cluster", cov_kwds={"groups": sub["gvkey"]})
    lo, hi = res.conf_int().loc[x]
    return {"coef": res.params[x], "ci_lo": lo, "ci_hi": hi, "n": int(res.nobs)}


def coefficient_table(df: pd.DataFrame, coefs_path) -> tuple:
    """Prefer the SAS estimates; fall back to re-estimating in Python."""
    if coefs_path and os.path.exists(coefs_path):
        sas = pd.read_csv(coefs_path)
        rows = []
        for label, (col, tag) in PILLARS.items():
            hit = sas[(sas["model"].str.strip() == tag)
                      & (sas["Parameter"].str.strip().str.lower() == col.lower())]
            if hit.empty:
                break
            r = hit.iloc[0]
            rows.append({"pillar": label, "coef": r["Estimate"],
                         "ci_lo": r["LowerCL"], "ci_hi": r["UpperCL"]})
        else:
            return pd.DataFrame(rows), "SAS PROC SURVEYREG estimates"
        print(f"WARNING: {coefs_path} lacks some ENCI rows; re-estimating in Python.")

    rows = [{"pillar": label, **fe_coefficient(df, col)}
            for label, (col, _) in PILLARS.items()]
    return pd.DataFrame(rows), "re-estimated in Python (statsmodels)"


def build_dashboard(df: pd.DataFrame, out_path: str, coefs_path=None):
    synthetic = ("data_source" in df.columns
                 and df["data_source"].astype(str).str.lower().eq("synthetic").any())
    enci_df = df.dropna(subset=["ENCI", "ABS_DAC", "ESG_INTENSITY"])
    yr_min, yr_max = int(df["fyear"].min()), int(df["fyear"].max())
    enci_min, enci_max = int(enci_df["fyear"].min()), int(enci_df["fyear"].max())

    # ---- Panel 1: ENCI vs |DAC| scatter with pooled OLS line (descriptive) ----
    sample = enci_df.sample(min(4000, len(enci_df)), random_state=0)
    slope, intercept = np.polyfit(enci_df["ENCI"], enci_df["ABS_DAC"], 1)
    x_range = np.linspace(enci_df["ENCI"].min(), enci_df["ENCI"].max(), 50)

    scatter = go.Scatter(
        x=sample["ENCI"], y=sample["ABS_DAC"], mode="markers",
        marker=dict(size=5, opacity=0.45, color=sample["ESG_INTENSITY"],
                    colorscale="Viridis",
                    colorbar=dict(title="ESG<br>Intensity", x=1.0, len=0.42, y=0.79)),
        name="Firm-year",
        hovertemplate="ENCI=%{x:.2f}<br>|DAC|=%{y:.3f}<extra></extra>",
    )
    trend1 = go.Scatter(x=x_range, y=intercept + slope * x_range, mode="lines",
                        line=dict(color="firebrick", width=3),
                        name="Pooled OLS (descriptive)")

    # ---- Panel 2: ESG intensity by section over time ----
    trend_yr = df.groupby("fyear")[["esg_int_mda", "esg_int_rf"]].mean().reset_index()
    mda_line = go.Scatter(x=trend_yr["fyear"], y=trend_yr["esg_int_mda"],
                          mode="lines+markers", name="MD&A section",
                          line=dict(color="#2a6f97", width=3))
    rf_line = go.Scatter(x=trend_yr["fyear"], y=trend_yr["esg_int_rf"],
                         mode="lines+markers", name="Risk Factors (Item 1A)",
                         line=dict(color="#bb3e03", width=3))

    # ---- Panel 3: ENCI coefficients, firm + year FE, clustered 95% CI ----
    coef_df, coef_source = coefficient_table(df, coefs_path)
    bar = go.Bar(
        x=coef_df["pillar"], y=coef_df["coef"],
        error_y=dict(type="data",
                     array=coef_df["ci_hi"] - coef_df["coef"],
                     arrayminus=coef_df["coef"] - coef_df["ci_lo"]),
        marker_color=["#264653", "#2a9d8f", "#e9c46a", "#e76f51"],
        name="ENCI coefficient on |DAC|",
        hovertemplate="%{x}<br>coef=%{y:.4f}<extra></extra>",
    )

    # ---- Panel 4: ESG intensity x ENCI quintile heatmap ----
    heat_df = enci_df.copy()
    labels = [f"Q{i}" for i in range(1, 6)]
    heat_df["esg_bin"] = pd.qcut(heat_df["ESG_INTENSITY"], 5, labels=labels)
    heat_df["enci_bin"] = pd.qcut(heat_df["ENCI"], 5, labels=labels)
    pivot = heat_df.pivot_table(values="ABS_DAC", index="esg_bin", columns="enci_bin",
                                aggfunc="mean", observed=False).sort_index(ascending=False)
    heat = go.Heatmap(
        z=pivot.values,
        x=[f"ENCI {c}<br>(least\u2192most consistent)" if c == "Q1" else f"ENCI {c}"
           for c in pivot.columns],
        y=[f"ESG {r}<br>(low\u2192high)" if r == "Q1" else f"ESG {r}" for r in pivot.index],
        colorscale="RdYlGn_r",
        colorbar=dict(title="Mean<br>|DAC|", x=1.0, len=0.42, y=0.21),
        hovertemplate="%{x} / %{y}<br>mean |DAC|=%{z:.3f}<extra></extra>",
    )

    # ---- Assemble ----
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            f"1. ENCI vs. |Discretionary Accruals|  (H1), FY{enci_min}\u2013{enci_max}",
            f"2. ESG Disclosure Intensity by Section, FY{yr_min}\u2013{yr_max}",
            "3. ENCI Coefficients on |DAC| (firm & year FE, clustered 95% CI)",
            "4. ESG Intensity \u00d7 ENCI \u2192 Mean |DAC|  (H2)",
        ),
        specs=[[{"type": "scatter"}, {"type": "scatter"}],
               [{"type": "bar"}, {"type": "heatmap"}]],
        horizontal_spacing=0.12, vertical_spacing=0.14,
    )
    fig.add_trace(scatter, row=1, col=1)
    fig.add_trace(trend1, row=1, col=1)
    fig.add_trace(mda_line, row=1, col=2)
    fig.add_trace(rf_line, row=1, col=2)
    fig.add_trace(bar, row=2, col=1)
    fig.add_trace(heat, row=2, col=2)

    fig.update_xaxes(title_text="ENCI (ESG Narrative Consistency)", row=1, col=1)
    fig.update_yaxes(title_text="|Discretionary Accruals|", row=1, col=1)
    fig.update_xaxes(title_text="Fiscal Year", row=1, col=2)
    fig.update_yaxes(title_text="Mean ESG word intensity", row=1, col=2)
    fig.add_vline(x=ITEM_1A_FYEAR - 0.5, line_dash="dot", line_color="gray",
                  annotation_text="Item 1A required", annotation_position="top left",
                  row=1, col=2)
    fig.update_xaxes(title_text=f"ESG Pillar  \u00b7  {coef_source}", row=2, col=1)
    fig.update_yaxes(title_text="Coefficient on |DAC|", row=2, col=1)
    fig.add_hline(y=0, line_dash="dot", line_color="gray", row=2, col=1)

    title = ("ESG Narrative Consistency and Discretionary Accruals \u2014 "
             f"S&P 500, FY{yr_min}\u2013{yr_max}")
    subtitle = "Albert Limani \u00b7 Pace University ACC 692Q"
    if synthetic:
        title = "SYNTHETIC DEMO DATA \u2014 " + title
        subtitle += " \u00b7 simulated data, NOT empirical results"

    fig.update_layout(
        height=900, width=1150,
        title=dict(text=f"{title}<br><sup>{subtitle}</sup>",
                   x=0.5, xanchor="center", font=dict(size=18)),
        legend=dict(orientation="h", yanchor="bottom", y=1.06, xanchor="center", x=0.78),
        template="plotly_white",
        margin=dict(t=130),
    )
    if synthetic:
        fig.add_annotation(text="SYNTHETIC DATA", xref="paper", yref="paper",
                           x=0.5, y=0.5, showarrow=False, textangle=-25,
                           font=dict(size=96, color="rgba(200,0,0,0.12)"))

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    fig.write_html(out_path, include_plotlyjs="cdn")
    print(f"Dashboard written to {out_path}  (panel 3: {coef_source}"
          f"{'; SYNTHETIC watermark' if synthetic else ''})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build the ENCI / DAC interactive dashboard")
    parser.add_argument("--input", type=str, default=None,
                        help="Cleaned panel CSV. Defaults to data/sample_panel.csv")
    parser.add_argument("--coefs", type=str, default="data/coefficients.csv",
                        help="SAS coefficient CSV from data_pipeline.py (used if it exists)")
    parser.add_argument("--out", type=str, default="outputs/enci_dashboard.html")
    args = parser.parse_args()

    input_path = args.input or "data/sample_panel.csv"
    if not os.path.exists(input_path):
        raise FileNotFoundError(
            f"{input_path} not found. Run generate_sample_data.py first, or "
            "pass --input pointing to your SAS-exported panel (run "
            "data_pipeline.py to clean it first).")

    build_dashboard(pd.read_csv(input_path), args.out, args.coefs)
