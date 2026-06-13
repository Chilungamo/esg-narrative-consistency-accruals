"""
visualize.py

Builds a single self-contained interactive HTML dashboard summarizing the
core empirical results of the ESG Narrative Consistency / Discretionary
Accruals study:

  1. ENCI vs |DAC| scatter (H1), colored by ESG intensity, with OLS trendline
  2. ESG intensity trends 1994-2024 (MD&A vs Risk Factor sections)
  3. Sub-pillar (E/S/G) ENCI coefficient plot with confidence intervals
  4. ESG intensity x ENCI interaction heatmap on mean |DAC| (H2)

Usage:
    python visualize.py --input data/panel_clean.csv --out outputs/enci_dashboard.html

If --input is omitted, falls back to data/sample_panel.csv (run
generate_sample_data.py first).
"""

import argparse
import os

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots
import statsmodels.api as sm


def fit_ols(df, y, x_cols):
    X = sm.add_constant(df[x_cols])
    model = sm.OLS(df[y], X, missing="drop").fit()
    return model


def build_dashboard(df: pd.DataFrame, out_path: str):
    # ---- Panel 1: ENCI vs |DAC| scatter with OLS trendline ----
    sample = df.sample(min(4000, len(df)), random_state=0)
    ols1 = fit_ols(df, "ABS_DAC", ["ENCI"])
    x_range = np.linspace(df["ENCI"].min(), df["ENCI"].max(), 50)
    y_pred = ols1.params["const"] + ols1.params["ENCI"] * x_range

    scatter = go.Scatter(
        x=sample["ENCI"], y=sample["ABS_DAC"],
        mode="markers",
        marker=dict(
            size=5, opacity=0.45,
            color=sample["ESG_INTENSITY"],
            colorscale="Viridis",
            colorbar=dict(title="ESG<br>Intensity", x=1.0, len=0.42, y=0.79),
        ),
        name="Firm-year",
        hovertemplate="ENCI=%{x:.2f}<br>|DAC|=%{y:.3f}<extra></extra>",
    )
    trend1 = go.Scatter(
        x=x_range, y=y_pred, mode="lines",
        line=dict(color="firebrick", width=3),
        name="OLS fit",
    )

    # ---- Panel 2: ESG intensity trends over time ----
    trend_yr = df.groupby("fyear")[["esg_int_mda", "esg_int_rf"]].mean().reset_index()
    mda_line = go.Scatter(
        x=trend_yr["fyear"], y=trend_yr["esg_int_mda"],
        mode="lines+markers", name="MD&A section",
        line=dict(color="#2a6f97", width=3),
    )
    rf_line = go.Scatter(
        x=trend_yr["fyear"], y=trend_yr["esg_int_rf"],
        mode="lines+markers", name="Risk Factors section",
        line=dict(color="#bb3e03", width=3),
    )

    # ---- Panel 3: Sub-pillar ENCI coefficients with 95% CI ----
    pillars = {
        "Overall": "ENCI",
        "Environmental": "ENCI_env",
        "Social": "ENCI_soc",
        "Governance": "ENCI_gov",
    }
    coef_rows = []
    for label, col in pillars.items():
        sub = df.dropna(subset=[col, "ABS_DAC", "SIZE", "LEVERAGE", "MTB", "ROA"])
        model = fit_ols(sub, "ABS_DAC", [col, "SIZE", "LEVERAGE", "MTB", "ROA"])
        coef = model.params[col]
        ci_lo, ci_hi = model.conf_int().loc[col]
        coef_rows.append({"pillar": label, "coef": coef, "ci_lo": ci_lo, "ci_hi": ci_hi})
    coef_df = pd.DataFrame(coef_rows)

    bar = go.Bar(
        x=coef_df["pillar"], y=coef_df["coef"],
        error_y=dict(
            type="data",
            array=coef_df["ci_hi"] - coef_df["coef"],
            arrayminus=coef_df["coef"] - coef_df["ci_lo"],
        ),
        marker_color=["#264653", "#2a9d8f", "#e9c46a", "#e76f51"],
        name="ENCI coefficient on |DAC|",
        hovertemplate="%{x}<br>coef=%{y:.4f}<extra></extra>",
    )

    # ---- Panel 4: ESG intensity x ENCI interaction heatmap ----
    heat_df = df.dropna(subset=["ESG_INTENSITY", "ENCI", "ABS_DAC"]).copy()
    heat_df["esg_bin"] = pd.qcut(heat_df["ESG_INTENSITY"], 5,
                                  labels=[f"Q{i}" for i in range(1, 6)])
    heat_df["enci_bin"] = pd.qcut(heat_df["ENCI"], 5,
                                   labels=[f"Q{i}" for i in range(1, 6)])
    pivot = heat_df.pivot_table(
        values="ABS_DAC", index="esg_bin", columns="enci_bin", aggfunc="mean"
    ).sort_index(ascending=False)

    heat = go.Heatmap(
        z=pivot.values,
        x=[f"ENCI {c}<br>(low\u2192high)" if c == "Q1" else f"ENCI {c}" for c in pivot.columns],
        y=[f"ESG {r}<br>(low\u2192high)" if r == "Q1" else f"ESG {r}" for r in pivot.index],
        colorscale="RdYlGn_r",
        colorbar=dict(title="Mean<br>|DAC|", x=1.0, len=0.42, y=0.21),
        hovertemplate="%{x} / %{y}<br>mean |DAC|=%{z:.3f}<extra></extra>",
    )

    # ---- Assemble subplots ----
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            "1. ENCI vs. |Discretionary Accruals|  (H1)",
            "2. ESG Disclosure Intensity, 1994\u20132024",
            "3. Sub-pillar ENCI Coefficients on |DAC|",
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
    fig.update_xaxes(title_text="ESG Pillar", row=2, col=1)
    fig.update_yaxes(title_text="Coefficient on |DAC|", row=2, col=1)
    fig.add_hline(y=0, line_dash="dot", line_color="gray", row=2, col=1)

    fig.update_layout(
        height=900, width=1150,
        title=dict(
            text="ESG Narrative Consistency and Discretionary Accruals \u2014 "
                 "S&P 500, 1994\u20132024<br>"
                 "<sup>Albert Limani \u00b7 Pace University ACC 692Q</sup>",
            x=0.5, xanchor="center", font=dict(size=20),
        ),
        legend=dict(orientation="h", yanchor="bottom", y=1.06, xanchor="center", x=0.78),
        template="plotly_white",
        margin=dict(t=130),
    )

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    fig.write_html(out_path, include_plotlyjs="cdn")
    print(f"Dashboard written to {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build the ENCI / DAC interactive dashboard")
    parser.add_argument("--input", type=str, default=None,
                         help="Path to cleaned panel CSV. Defaults to data/sample_panel.csv")
    parser.add_argument("--out", type=str, default="outputs/enci_dashboard.html")
    args = parser.parse_args()

    input_path = args.input or "data/sample_panel.csv"
    if not os.path.exists(input_path):
        raise FileNotFoundError(
            f"{input_path} not found. Run generate_sample_data.py first, or "
            "pass --input pointing to your SAS-exported panel (run "
            "data_pipeline.py to clean it first)."
        )

    df = pd.read_csv(input_path)
    build_dashboard(df, args.out)
