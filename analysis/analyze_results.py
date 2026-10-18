from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


REQUIRED_COLUMNS = {
    "agents_initiaux",
    "largeur_porte_m",
    "force",
    "pilier",
    "temps_total_s",
}


def load_summary(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path)
    missing = REQUIRED_COLUMNS.difference(frame.columns)
    if missing:
        raise ValueError(f"Colonnes absentes du CSV: {', '.join(sorted(missing))}")
    frame = frame.copy()
    frame["pilier"] = frame["pilier"].astype(str).str.lower().map(
        {"true": True, "1": True, "yes": True, "false": False, "0": False, "no": False}
    )
    frame["temps_total_s"] = pd.to_numeric(frame["temps_total_s"], errors="coerce")
    frame["force"] = pd.to_numeric(frame["force"], errors="coerce")
    frame["largeur_porte_m"] = pd.to_numeric(frame["largeur_porte_m"], errors="coerce")
    frame["agents_initiaux"] = pd.to_numeric(frame["agents_initiaux"], errors="coerce")
    if "sorties_configurees" in frame.columns:
        frame["sorties_configurees"] = pd.to_numeric(frame["sorties_configurees"], errors="coerce").fillna(1)
    else:
        frame["sorties_configurees"] = 1
    if "statut" not in frame.columns:
        frame["statut"] = "complete"
    frame["statut"] = frame["statut"].fillna("complete").astype(str).str.lower()
    frame = frame.dropna(subset=["force", "largeur_porte_m", "agents_initiaux", "pilier"])
    timeout_count = int((frame["statut"] == "timeout").sum())
    print(f"Essais timeout exclus des moyennes: {timeout_count}")
    frame = frame[(frame["statut"] == "complete") & frame["temps_total_s"].notna()]
    frame = frame[frame["temps_total_s"] > 0]
    if frame.empty:
        raise ValueError("Le CSV ne contient aucune simulation complete exploitable.")
    return frame


def save_force_plot(frame: pd.DataFrame, output_dir: Path) -> None:
    subset = frame[(frame["agents_initiaux"] == frame["agents_initiaux"].max()) & (~frame["pilier"]) & (frame["sorties_configurees"] == 1)]
    if subset["force"].nunique() < 2:
        print("Courbe force: il faut au moins deux valeurs de force sans pilier avec une sortie.")
        return
    stats = subset.groupby("force")["temps_total_s"].agg(["mean", "std", "count"]).reset_index()
    stats["std"] = stats["std"].fillna(0)
    figure, axis = plt.subplots(figsize=(8, 5))
    axis.errorbar(stats["force"], stats["mean"], yerr=stats["std"], marker="o", capsize=4, color="#bf563f")
    axis.set(title="Temps d’evacuation selon la force", xlabel="Force appliquee", ylabel="Temps total (s)")
    axis.grid(True, alpha=0.25)
    figure.tight_layout()
    figure.savefig(output_dir / "force_vs_evacuation_time.png", dpi=180)
    plt.close(figure)


def save_width_plot(frame: pd.DataFrame, output_dir: Path) -> None:
    subset = frame[(frame["agents_initiaux"] == frame["agents_initiaux"].max()) & (~frame["pilier"]) & (frame["sorties_configurees"] == 1)]
    if subset["largeur_porte_m"].nunique() < 2:
        print("Largeur de porte: il faut au moins deux largeurs differentes sans pilier avec une sortie.")
        return
    subset = subset.assign(debit_moyen_agents_s=subset["agents_initiaux"] / subset["temps_total_s"])
    stats = subset.groupby("largeur_porte_m")["debit_moyen_agents_s"].agg(["mean", "std"]).reset_index()
    stats["std"] = stats["std"].fillna(0)
    figure, axis = plt.subplots(figsize=(8, 5))
    axis.errorbar(stats["largeur_porte_m"], stats["mean"], yerr=stats["std"], marker="o", capsize=4, color="#357b78")
    axis.set(title="Debit moyen selon la largeur de la porte", xlabel="Largeur de porte (m)", ylabel="Debit moyen (agents/s)")
    axis.grid(True, alpha=0.25)
    figure.tight_layout()
    figure.savefig(output_dir / "door_width_vs_flow.png", dpi=180)
    plt.close(figure)


def save_pillar_plot(frame: pd.DataFrame, output_dir: Path) -> None:
    subset = frame[(frame["agents_initiaux"] == frame["agents_initiaux"].max()) & (frame["sorties_configurees"] == 1)]
    if subset["pilier"].nunique() < 2:
        print("Pilier: il faut des simulations avec et sans pilier avec une sortie.")
        return
    stats = subset.groupby(["force", "pilier"])["temps_total_s"].agg(["mean", "std"]).reset_index()
    figure, axis = plt.subplots(figsize=(8, 5))
    for enabled, label, color in [(False, "Sans pilier", "#357b78"), (True, "Avec pilier", "#bf563f")]:
        series = stats[stats["pilier"] == enabled]
        if not series.empty:
            axis.errorbar(series["force"], series["mean"], yerr=series["std"].fillna(0), marker="o", capsize=4, label=label, color=color)
    axis.set(title="Effet du pilier sur le temps d’evacuation", xlabel="Force appliquee", ylabel="Temps total (s)")
    axis.legend()
    axis.grid(True, alpha=0.25)
    figure.tight_layout()
    figure.savefig(output_dir / "pillar_effect.png", dpi=180)
    plt.close(figure)


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyse les simulations d’evacuation Godot et exporte les graphiques.")
    parser.add_argument("summary_csv", type=Path, help="Chemin vers evacuation_summary.csv")
    parser.add_argument("--output", type=Path, default=Path("analysis/output"), help="Dossier des graphiques PNG")
    args = parser.parse_args()

    frame = load_summary(args.summary_csv)
    args.output.mkdir(parents=True, exist_ok=True)
    stats = frame.groupby(["agents_initiaux", "largeur_porte_m", "force", "pilier", "sorties_configurees"])["temps_total_s"].agg(["mean", "std", "count"])
    print(stats.to_string())
    save_force_plot(frame, args.output)
    save_width_plot(frame, args.output)
    save_pillar_plot(frame, args.output)
    print(f"Graphiques enregistres dans: {args.output.resolve()}")


if __name__ == "__main__":
    main()