#!/usr/bin/env python3
"""Generate thesis figures from benchmark analysis CSV outputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.colors import TwoSlopeNorm
from matplotlib.ticker import FormatStrFormatter
import pandas as pd


LOAD_ORDER = ["L1", "L2", "L3"]
S3_LOAD_ORDER = ["L2", "L3"]
LATENCY_METRICS = ["p50_ms", "p90_ms", "p99_ms"]
METRIC_LABELS = {"p50_ms": "p50", "p90_ms": "p90", "p99_ms": "p99"}
S3_PHASE_ORDER = ["off", "on"]
PHASE_ORDER = [
    "phase1_rampup",
    "phase2_sustained",
    "phase3_burst1",
    "phase3_burst2",
    "phase3_burst3",
    "phase4_cooldown",
]
PHASE_LABELS = {
    "phase1_rampup": "Ramp-up",
    "phase2_sustained": "Sustained",
    "phase3_burst1": "Burst 1",
    "phase3_burst2": "Burst 2",
    "phase3_burst3": "Burst 3",
    "phase4_cooldown": "Cooldown",
}
CALIBRATION_LOADS = {"L1": 100, "L2": 400, "L3": 800}
MODE_LABELS = {
    "A": "Mode A: Cilium + kube-proxy",
    "B": "Mode B: Cilium eBPF KPR",
}
MODE_COLORS = {"A": "#1f77b4", "B": "#d62728"}
POLICY_LABELS = {"off": "Policy OFF", "on": "Policy ON"}
POLICY_COLORS = {"off": "#1f77b4", "on": "#d62728"}


plt.rcParams.update(
    {
        "figure.dpi": 120,
        "savefig.dpi": 300,
        "font.size": 11,
        "axes.titlesize": 13,
        "axes.labelsize": 11,
        "legend.fontsize": 10,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "axes.spines.top": False,
        "axes.spines.right": False,
    }
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def require_columns(df: pd.DataFrame, columns: list[str], source: Path) -> None:
    missing = [col for col in columns if col not in df.columns]
    if missing:
        raise ValueError(f"{source} is missing required columns: {', '.join(missing)}")


def load_csvs(analysis_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    aggregated_path = analysis_dir / "aggregated_summary.csv"
    comparison_path = analysis_dir / "comparison_AB.csv"

    if not aggregated_path.exists():
        raise FileNotFoundError(f"Missing input CSV: {aggregated_path}")
    if not comparison_path.exists():
        raise FileNotFoundError(f"Missing input CSV: {comparison_path}")

    aggregated = pd.read_csv(aggregated_path)
    comparison = pd.read_csv(comparison_path)

    require_columns(aggregated, ["group"], aggregated_path)
    require_columns(
        comparison,
        [
            "scenario",
            "load",
            "phase",
            "metric",
            "A_mean",
            "A_ci_lo",
            "A_ci_hi",
            "B_mean",
            "B_ci_lo",
            "B_ci_hi",
            "delta_pct",
            "significant",
        ],
        comparison_path,
    )

    numeric_columns = [
        "A_mean",
        "A_ci_lo",
        "A_ci_hi",
        "B_mean",
        "B_ci_lo",
        "B_ci_hi",
        "delta_pct",
    ]
    for column in numeric_columns:
        comparison[column] = pd.to_numeric(comparison[column], errors="coerce")

    comparison["phase"] = comparison["phase"].fillna("")
    comparison["significant"] = comparison["significant"].fillna("")
    return aggregated, comparison


def save_fig(fig: plt.Figure, output_dir: Path, basename: str) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [output_dir / f"{basename}.png", output_dir / f"{basename}.pdf"]
    fig.savefig(outputs[0], dpi=300, bbox_inches="tight")
    fig.savefig(outputs[1], bbox_inches="tight")
    plt.close(fig)
    for output in outputs:
        print(f"generated: {output}")
    return outputs


def ci_yerr(rows: pd.DataFrame, prefix: str) -> list[list[float]] | None:
    mean_col = f"{prefix}_mean"
    lo_col = f"{prefix}_ci_lo"
    hi_col = f"{prefix}_ci_hi"
    if not {mean_col, lo_col, hi_col}.issubset(rows.columns):
        return None
    values = rows[[mean_col, lo_col, hi_col]]
    if values.isna().any().any():
        return None
    lower = (values[mean_col] - values[lo_col]).clip(lower=0).tolist()
    upper = (values[hi_col] - values[mean_col]).clip(lower=0).tolist()
    return [lower, upper]


def ordered_s1_metric_rows(comparison: pd.DataFrame, metric: str) -> pd.DataFrame:
    rows = comparison[
        (comparison["scenario"] == "S1")
        & (comparison["load"].isin(LOAD_ORDER))
        & (comparison["metric"] == metric)
    ].copy()
    rows["load"] = pd.Categorical(rows["load"], categories=LOAD_ORDER, ordered=True)
    rows = rows.sort_values("load")

    expected = len(LOAD_ORDER)
    if len(rows) != expected:
        raise ValueError(f"S1 {metric} rows incomplete: expected {expected}, found {len(rows)}")
    return rows


def chart_s1_p99_vs_load(comparison: pd.DataFrame, output_dir: Path) -> list[Path]:
    rows = ordered_s1_metric_rows(comparison, "p99_ms")
    x = list(range(len(rows)))

    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for mode in ["A", "B"]:
        ax.errorbar(
            x,
            rows[f"{mode}_mean"],
            yerr=ci_yerr(rows, mode),
            marker="o",
            linewidth=2.0,
            capsize=4,
            color=MODE_COLORS[mode],
            label=MODE_LABELS[mode],
        )

    ax.set_title("S1 p99 latency vs load")
    ax.set_xlabel("Load level")
    ax.set_ylabel("p99 latency (ms)")
    ax.set_xticks(x, LOAD_ORDER)
    ax.grid(axis="y", alpha=0.25)
    ax.legend(loc="upper left")
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s1-p99-vs-load")


def chart_s1_latency_small_multiples(comparison: pd.DataFrame, output_dir: Path) -> list[Path]:
    fig, axes = plt.subplots(1, 3, figsize=(12.5, 4.1), sharex=True)

    for ax, metric in zip(axes, LATENCY_METRICS):
        rows = ordered_s1_metric_rows(comparison, metric)
        x = list(range(len(rows)))
        for mode in ["A", "B"]:
            ax.errorbar(
                x,
                rows[f"{mode}_mean"],
                yerr=ci_yerr(rows, mode),
                marker="o",
                linewidth=1.9,
                capsize=3,
                color=MODE_COLORS[mode],
                label=MODE_LABELS[mode],
            )
        ax.set_title(METRIC_LABELS[metric])
        ax.set_xlabel("Load level")
        ax.set_xticks(x, LOAD_ORDER)
        ax.grid(axis="y", alpha=0.25)

    axes[0].set_ylabel("Latency (ms)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=2, frameon=False, bbox_to_anchor=(0.5, 1.04))
    fig.suptitle("S1 latency percentiles vs load", y=1.13)
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s1-latency-small-multiples")


def chart_s1_delta_p99(comparison: pd.DataFrame, output_dir: Path) -> list[Path]:
    rows = ordered_s1_metric_rows(comparison, "p99_ms")
    x = list(range(len(rows)))

    fig, ax = plt.subplots(figsize=(7.2, 4.2))
    colors = [MODE_COLORS["A"] if value <= 0 else MODE_COLORS["B"] for value in rows["delta_pct"]]
    ax.bar(x, rows["delta_pct"], color=colors, width=0.55)
    ax.axhline(0, color="black", linewidth=0.9)

    span = max(float(rows["delta_pct"].max() - rows["delta_pct"].min()), 1.0)
    marker_offset = span * 0.08
    for idx, row in enumerate(rows.itertuples()):
        if str(row.significant).upper() == "YES":
            y = row.delta_pct + marker_offset if row.delta_pct >= 0 else row.delta_pct - marker_offset
            va = "bottom" if row.delta_pct >= 0 else "top"
            ax.text(idx, y, "*", ha="center", va=va, fontsize=15, fontweight="bold")

    ax.set_title("S1 p99 latency delta: Mode B vs Mode A")
    ax.set_xlabel("Load level")
    ax.set_ylabel("Delta (%)")
    ax.set_xticks(x, LOAD_ORDER)
    ax.grid(axis="y", alpha=0.25)
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s1-delta-p99")


def ordered_s2_phase_rows(comparison: pd.DataFrame, load: str) -> pd.DataFrame:
    rows = comparison[
        (comparison["scenario"] == "S2")
        & (comparison["load"] == load)
        & (comparison["metric"] == "p99_ms")
        & (comparison["phase"].isin(PHASE_ORDER))
    ].copy()
    rows["phase"] = pd.Categorical(rows["phase"], categories=PHASE_ORDER, ordered=True)
    rows = rows.sort_values("phase")

    if len(rows) != len(PHASE_ORDER):
        raise ValueError(f"S2 {load} p99 phase rows incomplete: expected {len(PHASE_ORDER)}, found {len(rows)}")
    return rows


def chart_s2_phase_p99(comparison: pd.DataFrame, output_dir: Path, load: str) -> list[Path]:
    rows = ordered_s2_phase_rows(comparison, load)
    x = list(range(len(rows)))
    labels = [PHASE_LABELS[str(phase)] for phase in rows["phase"]]

    fig, ax = plt.subplots(figsize=(8.8, 4.6))
    for mode in ["A", "B"]:
        ax.errorbar(
            x,
            rows[f"{mode}_mean"],
            yerr=ci_yerr(rows, mode),
            marker="o",
            capsize=4,
            linewidth=2.0,
            color=MODE_COLORS[mode],
            label=MODE_LABELS[mode],
        )

    ax.set_title(f"S2 phase-aware p99 latency ({load})")
    ax.set_xlabel("S2 phase")
    ax.set_ylabel("p99 latency (ms)")
    ax.set_xticks(x, labels, rotation=18, ha="right")
    ax.legend(loc="upper left")
    ax.grid(axis="y", alpha=0.25)
    fig.tight_layout()
    return save_fig(fig, output_dir, f"fig-s2-phase-p99-{load.lower()}")


def fortio_percentile_ms(path: Path, percentile: float) -> float:
    data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    for item in data.get("DurationHistogram", {}).get("Percentiles", []):
        if abs(float(item["Percentile"]) - percentile) < 1e-9:
            # Fortio JSON stores latency percentiles in seconds.
            return float(item["Value"]) * 1000.0
    raise ValueError(f"{path} is missing percentile {percentile}")


def run_id_from_path(path: Path) -> str:
    for part in path.parts:
        if part.startswith("run="):
            return part.split("=", 1)[1].split("_", 1)[0]
    return path.parent.name


def repeatability_raw_p99(repo: Path) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    mode_dirs = {
        "A": repo / "results" / "mode=A_kube-proxy",
        "B": repo / "results" / "mode=B_cilium-ebpfkpr",
    }
    mode_names = {"A": "Mode A", "B": "Mode B"}

    sort_order = 0
    for mode, mode_dir in mode_dirs.items():
        paths = sorted((mode_dir / "scenario=S1" / "load=L3").glob("run=*/fortio.json"))
        if len(paths) != 3:
            raise ValueError(f"Expected 3 S1 L3 runs for {mode}, found {len(paths)}")
        for path in paths:
            records.append(
                {
                    "scenario": "S1",
                    "load": "L3",
                    "phase": "",
                    "mode": mode_names[mode],
                    "policy_state": "",
                    "group_label": f"S1 L3 - {mode_names[mode]}",
                    "run_id": run_id_from_path(path),
                    "p99_ms": fortio_percentile_ms(path, 99.0),
                    "source_file": str(path),
                    "sort_order": sort_order,
                }
            )
        sort_order += 1

    for load in ["L2", "L3"]:
        for phase in PHASE_ORDER:
            for mode, mode_dir in mode_dirs.items():
                paths = sorted((mode_dir / "scenario=S2" / f"load={load}").glob(f"run=*/fortio_{phase}.json"))
                if len(paths) != 3:
                    raise ValueError(f"Expected 3 S2 {load} {phase} runs for {mode}, found {len(paths)}")
                for path in paths:
                    records.append(
                        {
                            "scenario": "S2",
                            "load": load,
                            "phase": phase,
                            "mode": mode_names[mode],
                            "policy_state": "",
                            "group_label": f"S2 {load} {PHASE_LABELS[phase]} - {mode_names[mode]}",
                            "run_id": run_id_from_path(path),
                            "p99_ms": fortio_percentile_ms(path, 99.0),
                            "source_file": str(path),
                            "sort_order": sort_order,
                        }
                    )
                sort_order += 1

    s3_dir = mode_dirs["B"] / "scenario=S3" / "load=L3"
    for policy_state in S3_PHASE_ORDER:
        paths = sorted((s3_dir / f"phase={policy_state}").glob("run=*/fortio.json"))
        if len(paths) != 3:
            raise ValueError(f"Expected 3 S3 L3 {policy_state} runs, found {len(paths)}")
        for path in paths:
            records.append(
                {
                    "scenario": "S3",
                    "load": "L3",
                    "phase": "",
                    "mode": "Mode B",
                    "policy_state": policy_state,
                    "group_label": f"S3 L3 - Policy {policy_state.upper()}",
                    "run_id": run_id_from_path(path),
                    "p99_ms": fortio_percentile_ms(path, 99.0),
                    "source_file": str(path),
                    "sort_order": sort_order,
                }
            )
        sort_order += 1

    raw = pd.DataFrame.from_records(records)
    expected_rows = 84
    if len(raw) != expected_rows:
        raise ValueError(f"Unexpected repeatability raw row count: expected {expected_rows}, found {len(raw)}")
    return raw


def repeatability_summary(raw: pd.DataFrame) -> pd.DataFrame:
    summary = (
        raw.groupby(["scenario", "load", "phase", "mode", "policy_state", "group_label", "sort_order"], as_index=False)
        .agg(mean_p99_ms=("p99_ms", "mean"), stdev_p99_ms=("p99_ms", "std"), n=("p99_ms", "count"))
        .sort_values("sort_order")
    )
    summary["cv_pct"] = (summary["stdev_p99_ms"] / summary["mean_p99_ms"]) * 100.0
    columns = ["scenario", "load", "phase", "mode", "policy_state", "group_label", "mean_p99_ms", "stdev_p99_ms", "cv_pct", "n"]
    summary = summary[columns]
    for column in ["mean_p99_ms", "stdev_p99_ms", "cv_pct"]:
        summary[column] = summary[column].round(3)
    return summary


def write_repeatability_summary(raw: pd.DataFrame, analysis_dir: Path) -> list[Path]:
    analysis_dir.mkdir(parents=True, exist_ok=True)
    output = analysis_dir / "repeatability_summary.csv"
    repeatability_summary(raw).to_csv(output, index=False)
    print(f"generated: {output}")
    return [output]


def add_mean_line(ax: plt.Axes, x: float, values: pd.Series, width: float, color: str) -> None:
    mean_value = float(values.mean())
    ax.hlines(mean_value, x - width / 2, x + width / 2, color=color, linewidth=2.0)


def chart_repeatability_p99_dotplot(raw: pd.DataFrame, output_dir: Path) -> list[Path]:
    fig, axes = plt.subplots(
        3,
        1,
        figsize=(10.5, 10.5),
        gridspec_kw={"height_ratios": [1.0, 1.35, 1.35]},
    )
    jitter = [-0.035, 0.0, 0.035]

    overview_groups = [
        "S1 L3 - Mode A",
        "S1 L3 - Mode B",
        "S3 L3 - Policy OFF",
        "S3 L3 - Policy ON",
    ]
    overview_colors = {
        "S1 L3 - Mode A": MODE_COLORS["A"],
        "S1 L3 - Mode B": MODE_COLORS["B"],
        "S3 L3 - Policy OFF": POLICY_COLORS["off"],
        "S3 L3 - Policy ON": POLICY_COLORS["on"],
    }
    ax = axes[0]
    for idx, group in enumerate(overview_groups):
        rows = raw[raw["group_label"] == group].sort_values("run_id")
        for run_idx, row in enumerate(rows.itertuples(index=False)):
            ax.scatter(idx + jitter[run_idx], row.p99_ms, color=overview_colors[group], s=48)
        add_mean_line(ax, idx, rows["p99_ms"], 0.28, overview_colors[group])
    ax.set_title("Repeatability: p99 per raw run (representative groups)")
    ax.set_ylabel("p99 latency (ms)")
    ax.set_xticks(range(len(overview_groups)), overview_groups, rotation=12, ha="right")
    ax.grid(axis="y", alpha=0.25)

    for ax, load in zip(axes[1:], ["L2", "L3"]):
        for phase_idx, phase in enumerate(PHASE_ORDER):
            for mode, offset, color in [("Mode A", -0.13, MODE_COLORS["A"]), ("Mode B", 0.13, MODE_COLORS["B"])]:
                rows = raw[
                    (raw["scenario"] == "S2")
                    & (raw["load"] == load)
                    & (raw["phase"] == phase)
                    & (raw["mode"] == mode)
                ].sort_values("run_id")
                for run_idx, row in enumerate(rows.itertuples(index=False)):
                    label = mode if phase_idx == 0 and run_idx == 0 else None
                    ax.scatter(phase_idx + offset + jitter[run_idx], row.p99_ms, color=color, s=42, label=label)
                add_mean_line(ax, phase_idx + offset, rows["p99_ms"], 0.16, color)
        ax.set_title(f"S2 {load}: p99 repeatability by phase")
        ax.set_ylabel("p99 latency (ms)")
        ax.set_xticks(range(len(PHASE_ORDER)), [PHASE_LABELS[phase] for phase in PHASE_ORDER], rotation=18, ha="right")
        ax.grid(axis="y", alpha=0.25)
        ax.legend(loc="upper left")

    axes[-1].set_xlabel("Each dot is one raw final run; short horizontal ticks show group means.")
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-repeatability-p99-dotplot")


def s2_raw_p99_means(repo: Path) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    mode_dirs = {
        "A": repo / "results" / "mode=A_kube-proxy" / "scenario=S2",
        "B": repo / "results" / "mode=B_cilium-ebpfkpr" / "scenario=S2",
    }

    for mode, scenario_dir in mode_dirs.items():
        if not scenario_dir.exists():
            raise FileNotFoundError(f"Missing S2 raw results directory: {scenario_dir}")
        for load in ["L2", "L3"]:
            for phase in PHASE_ORDER:
                paths = sorted((scenario_dir / f"load={load}").glob(f"run=*/fortio_{phase}.json"))
                if not paths:
                    raise FileNotFoundError(f"Missing S2 raw Fortio JSON for mode={mode}, load={load}, phase={phase}")
                for path in paths:
                    records.append(
                        {
                            "mode": mode,
                            "load": load,
                            "phase": phase,
                            "p99_ms": fortio_percentile_ms(path, 99.0),
                            "path": str(path),
                        }
                    )

    raw = pd.DataFrame.from_records(records)
    expected_rows = 2 * 2 * len(PHASE_ORDER) * 3
    if len(raw) != expected_rows:
        raise ValueError(f"Unexpected S2 raw row count: expected {expected_rows}, found {len(raw)}")

    means = raw.groupby(["mode", "load", "phase"], as_index=False).agg(p99_ms=("p99_ms", "mean"))
    pivot = means.pivot_table(index=["load", "phase"], columns="mode", values="p99_ms", aggfunc="first").reset_index()
    if not {"A", "B"}.issubset(pivot.columns):
        raise ValueError("S2 raw p99 means must contain both Mode A and Mode B")
    pivot["delta_pct"] = ((pivot["B"] - pivot["A"]) / pivot["A"]) * 100.0
    return pivot


def chart_s2_p99_delta_heatmap(repo: Path, output_dir: Path) -> list[Path]:
    rows = s2_raw_p99_means(repo)
    heatmap = (
        rows.pivot(index="phase", columns="load", values="delta_pct")
        .reindex(index=PHASE_ORDER, columns=["L2", "L3"])
    )
    if heatmap.isna().any().any():
        raise ValueError("S2 p99 delta heatmap has missing cells")

    values = heatmap.to_numpy(dtype=float)
    max_abs = max(abs(float(values.min())), abs(float(values.max())), 1.0)
    norm = TwoSlopeNorm(vmin=-max_abs, vcenter=0.0, vmax=max_abs)

    fig, ax = plt.subplots(figsize=(6.8, 5.2))
    image = ax.imshow(values, cmap="RdBu_r", norm=norm, aspect="auto")

    ax.set_title("S2 p99 delta heatmap: Mode B vs Mode A")
    ax.set_xlabel("Load level")
    ax.set_ylabel("S2 phase")
    ax.set_xticks(range(len(heatmap.columns)), heatmap.columns)
    ax.set_yticks(range(len(heatmap.index)), [PHASE_LABELS[phase] for phase in heatmap.index])

    for row_idx, phase in enumerate(heatmap.index):
        for col_idx, load in enumerate(heatmap.columns):
            value = float(heatmap.loc[phase, load])
            text_color = "white" if abs(value) > max_abs * 0.45 else "black"
            ax.text(col_idx, row_idx, f"{value:+.1f}%", ha="center", va="center", color=text_color, fontsize=10)

    cbar = fig.colorbar(image, ax=ax, shrink=0.86)
    cbar.set_label("p99 delta, Mode B relative to Mode A (%)")
    ax.text(
        0.5,
        -0.13,
        "Negative means Mode B has lower p99 latency; positive means Mode B is higher.",
        transform=ax.transAxes,
        ha="center",
        va="top",
        fontsize=9,
    )
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s2-p99-delta-heatmap")


def ordered_s3_metric_rows(aggregated: pd.DataFrame, metric: str) -> pd.DataFrame:
    mean_col = f"{metric}_mean"
    lo_col = f"{metric}_ci_lo"
    hi_col = f"{metric}_ci_hi"
    require_columns(aggregated, ["group", mean_col, lo_col, hi_col], Path("aggregated_summary.csv"))

    records: list[dict[str, object]] = []
    for row in aggregated.itertuples(index=False):
        group = str(getattr(row, "group")).strip()
        parts = [part.strip() for part in group.split("+")]
        if len(parts) < 4:
            continue
        mode, scenario, load, phase = parts[:4]
        if mode == "B_cilium-ebpfkpr" and scenario == "S3" and load in S3_LOAD_ORDER and phase in S3_PHASE_ORDER:
            mean = pd.to_numeric(getattr(row, mean_col), errors="coerce")
            ci_lo = pd.to_numeric(getattr(row, lo_col), errors="coerce")
            ci_hi = pd.to_numeric(getattr(row, hi_col), errors="coerce")
            records.append({"load": load, "phase": phase, "mean": mean, "ci_lo": ci_lo, "ci_hi": ci_hi})

    rows = pd.DataFrame.from_records(records)
    expected = len(S3_LOAD_ORDER) * len(S3_PHASE_ORDER)
    if len(rows) != expected:
        raise ValueError(f"S3 {metric} rows incomplete: expected {expected}, found {len(rows)}")

    rows["load"] = pd.Categorical(rows["load"], categories=S3_LOAD_ORDER, ordered=True)
    rows["phase"] = pd.Categorical(rows["phase"], categories=S3_PHASE_ORDER, ordered=True)
    return rows.sort_values(["load", "phase"])


def s3_yerr(rows: pd.DataFrame) -> list[list[float]] | None:
    values = rows[["mean", "ci_lo", "ci_hi"]]
    if values.isna().any().any():
        return None
    lower = (values["mean"] - values["ci_lo"]).clip(lower=0).tolist()
    upper = (values["ci_hi"] - values["mean"]).clip(lower=0).tolist()
    return [lower, upper]


def chart_s3_policy_p99(aggregated: pd.DataFrame, output_dir: Path) -> list[Path]:
    rows = ordered_s3_metric_rows(aggregated, "p99_ms")
    x_base = {load: idx for idx, load in enumerate(S3_LOAD_ORDER)}
    offsets = {"off": -0.10, "on": 0.10}
    markers = {"off": "o", "on": "s"}

    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for phase in S3_PHASE_ORDER:
        phase_rows = rows[rows["phase"] == phase]
        x = [x_base[str(load)] + offsets[phase] for load in phase_rows["load"]]
        ax.errorbar(
            x,
            phase_rows["mean"],
            yerr=s3_yerr(phase_rows),
            fmt=markers[phase],
            linestyle="none",
            markersize=7,
            capsize=4,
            color=POLICY_COLORS[phase],
            label=POLICY_LABELS[phase],
        )

    for load in S3_LOAD_ORDER:
        load_rows = rows[rows["load"] == load].set_index("phase")
        off_mean = float(load_rows.loc["off", "mean"])
        on_mean = float(load_rows.loc["on", "mean"])
        delta_pct = ((on_mean - off_mean) / off_mean) * 100.0
        data_span = float(rows["ci_hi"].max() - rows["ci_lo"].min())
        y = float(load_rows["ci_hi"].max()) + data_span * 0.08
        ax.text(x_base[load], y, f"ON vs OFF: {delta_pct:+.1f}%", ha="center", fontsize=9)

    ax.set_title("S3 NetworkPolicy overhead: p99 latency")
    ax.set_xlabel("Load level")
    ax.set_ylabel("p99 latency (ms)")
    ax.set_xticks(list(x_base.values()), S3_LOAD_ORDER)
    ax.set_xlim(-0.45, len(S3_LOAD_ORDER) - 0.55)
    data_span = float(rows["ci_hi"].max() - rows["ci_lo"].min())
    ax.set_ylim(float(rows["ci_lo"].min()) - data_span * 0.08, float(rows["ci_hi"].max()) + data_span * 0.25)
    ax.grid(axis="y", alpha=0.25)
    ax.legend(loc="upper left")
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s3-policy-overhead-p99")


def chart_s3_policy_rps(aggregated: pd.DataFrame, output_dir: Path) -> list[Path]:
    rows = ordered_s3_metric_rows(aggregated, "rps")

    fig, axes = plt.subplots(1, len(S3_LOAD_ORDER), figsize=(8.6, 4.2), sharey=False)
    if len(S3_LOAD_ORDER) == 1:
        axes = [axes]

    for ax, load in zip(axes, S3_LOAD_ORDER):
        load_rows = rows[rows["load"] == load].sort_values("phase").reset_index(drop=True)
        x = list(range(len(S3_PHASE_ORDER)))
        yerr = s3_yerr(load_rows)

        for idx, phase in enumerate(S3_PHASE_ORDER):
            row = load_rows[load_rows["phase"] == phase].iloc[0]
            phase_yerr = None
            if yerr is not None:
                phase_yerr = [[yerr[0][idx]], [yerr[1][idx]]]
            ax.errorbar(
                [idx],
                [row["mean"]],
                yerr=phase_yerr,
                fmt="o",
                markersize=7,
                capsize=4,
                color=POLICY_COLORS[phase],
                label=POLICY_LABELS[phase] if load == S3_LOAD_ORDER[0] else None,
            )
            ax.text(idx, float(row["mean"]), f"{float(row['mean']):.3f}", ha="center", va="bottom", fontsize=9)

        target = 400.0 if load == "L2" else 800.0
        ax.axhline(target, color="0.45", linestyle="--", linewidth=1.0, alpha=0.8, label="Target RPS" if load == S3_LOAD_ORDER[0] else None)

        off_mean = float(load_rows[load_rows["phase"] == "off"]["mean"].iloc[0])
        on_mean = float(load_rows[load_rows["phase"] == "on"]["mean"].iloc[0])
        delta = on_mean - off_mean
        delta_pct = (delta / off_mean) * 100.0

        low = float(min(load_rows["ci_lo"].min(), target))
        high = float(max(load_rows["ci_hi"].max(), target))
        span = max(high - low, 0.03)
        ax.set_ylim(low - span * 0.35, high + span * 1.25)
        ax.text(0.5, high + span * 0.55, f"ON-OFF: {delta:+.3f} RPS ({delta_pct:+.4f}%)", ha="center", fontsize=9)

        ax.set_title(f"{load} target {target:.0f} RPS")
        ax.set_xticks(x, ["OFF", "ON"])
        ax.yaxis.set_major_formatter(FormatStrFormatter("%.3f"))
        ax.grid(axis="y", alpha=0.25)

    axes[0].set_ylabel("Achieved RPS")
    fig.suptitle("S3 NetworkPolicy overhead: achieved RPS (zoomed by load)", y=1.03)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=3, bbox_to_anchor=(0.5, -0.03))
    fig.tight_layout()
    return save_fig(fig, output_dir, "fig-s3-policy-overhead-rps")


def find_calibration_csv(repo: Path) -> Path | None:
    search_roots = [repo / "results" / "calibration", repo / "report" / "appendix"]
    candidates: list[Path] = []
    for search_root in search_roots:
        if not search_root.exists():
            continue
        for path in search_root.rglob("*.csv"):
            if "pilot" in {part.lower() for part in path.parts}:
                continue
            candidates.append(path)
    if not candidates:
        return None
    return max(candidates, key=lambda path: (path.stat().st_mtime, str(path)))


def load_calibration_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    require_columns(df, ["qps"], path)

    if "p99_ms" in df.columns:
        df["p99_latency_ms"] = pd.to_numeric(df["p99_ms"], errors="coerce")
    elif "p99" in df.columns:
        # Calibration percentile columns are Fortio seconds in the current CSV.
        df["p99_latency_ms"] = pd.to_numeric(df["p99"], errors="coerce") * 1000.0
    else:
        raise ValueError(f"{path} is missing required p99 latency column: p99_ms or p99")

    df["qps"] = pd.to_numeric(df["qps"], errors="coerce")
    if "error_rate_pct" in df.columns:
        df["error_rate_pct"] = pd.to_numeric(df["error_rate_pct"], errors="coerce")
    else:
        df["error_rate_pct"] = float("nan")
    return df.dropna(subset=["qps", "p99_latency_ms"])


def chart_calibration_curve(repo: Path, output_dir: Path) -> list[Path]:
    calibration_path = find_calibration_csv(repo)
    if calibration_path is None:
        print("skipped: fig-calibration-curve (no calibration CSV found)")
        return []

    df = load_calibration_csv(calibration_path)
    if df.empty:
        raise ValueError(f"{calibration_path} contains no usable qps/p99 calibration rows")

    grouped = (
        df.groupby("qps", as_index=False)
        .agg(p99_latency_ms=("p99_latency_ms", "mean"), error_rate_pct=("error_rate_pct", "mean"))
        .sort_values("qps")
    )

    fig, ax = plt.subplots(figsize=(7.8, 4.5))
    ax.plot(grouped["qps"], grouped["p99_latency_ms"], marker="o", linewidth=2.0, color=MODE_COLORS["A"])
    ax.set_title("Calibration curve")
    ax.set_xlabel("Target QPS")
    ax.set_ylabel("p99 latency (ms)")
    ax.grid(axis="y", alpha=0.25)

    y_top = float(grouped["p99_latency_ms"].max())
    for label, qps in CALIBRATION_LOADS.items():
        if grouped["qps"].min() <= qps <= grouped["qps"].max():
            ax.axvline(qps, color="gray", linestyle="--", linewidth=0.9, alpha=0.6)
            ax.text(qps, y_top, label, rotation=90, va="top", ha="right", fontsize=9, color="gray")

    nonzero_error = grouped["error_rate_pct"].fillna(0).abs().max() > 0
    if nonzero_error:
        ax2 = ax.twinx()
        ax2.plot(
            grouped["qps"],
            grouped["error_rate_pct"],
            marker="s",
            linestyle="--",
            color=MODE_COLORS["B"],
        )
        ax2.set_ylabel("Error rate (%)")
    else:
        ax.text(0.02, 0.96, "Error rate: 0%", transform=ax.transAxes, va="top", fontsize=10)

    fig.tight_layout()
    print(f"calibration source: {calibration_path}")
    return save_fig(fig, output_dir, "fig-calibration-curve")


def generate_all(repo: Path, analysis_dir: Path, output_dir: Path) -> list[Path]:
    aggregated, comparison = load_csvs(analysis_dir)
    repeatability_raw = repeatability_raw_p99(repo)

    generated: list[Path] = []
    generated.extend(write_repeatability_summary(repeatability_raw, analysis_dir))
    generated.extend(chart_s1_p99_vs_load(comparison, output_dir))
    generated.extend(chart_s1_latency_small_multiples(comparison, output_dir))
    generated.extend(chart_s1_delta_p99(comparison, output_dir))
    generated.extend(chart_s2_phase_p99(comparison, output_dir, "L2"))
    generated.extend(chart_s2_phase_p99(comparison, output_dir, "L3"))
    generated.extend(chart_s2_p99_delta_heatmap(repo, output_dir))
    generated.extend(chart_repeatability_p99_dotplot(repeatability_raw, output_dir))
    generated.extend(chart_s3_policy_p99(aggregated, output_dir))
    generated.extend(chart_s3_policy_rps(aggregated, output_dir))
    generated.extend(chart_calibration_curve(repo, output_dir))
    return generated


def parse_args() -> argparse.Namespace:
    root = repo_root()
    parser = argparse.ArgumentParser(description="Generate thesis figures from benchmark analysis CSVs.")
    parser.add_argument("--analysis-dir", type=Path, default=root / "results_analysis")
    parser.add_argument("--output-dir", type=Path, default=root / "docs" / "figures" / "thesis")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = repo_root()
    generated = generate_all(root, args.analysis_dir, args.output_dir)
    print(f"done: generated {len(generated)} file(s)")


if __name__ == "__main__":
    main()
