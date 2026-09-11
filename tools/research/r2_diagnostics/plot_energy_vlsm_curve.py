# -*- coding: utf-8 -*-
"""绘制 POD 能量 vs VLSM 数/检出率曲线，用于跨能量对比。

用法:
    python tools/research/r2_diagnostics/plot_energy_vlsm_curve.py <summary.json> --out curve.png

输入 JSON 由 summarize_attempts.py 生成，包含各 attempt 的 energy/vlsm_total/detection_rate。
对同一能量的多个 attempt（不同参数），绘制 marker 区分最优/非最优。
"""
import argparse
import json
import sys
from pathlib import Path

def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("summary_json", help="summarize_attempts.py 输出的 JSON")
    ap.add_argument("--out", default="energy_vlsm_curve.png", help="输出图片路径")
    ap.add_argument("--filter-energy", nargs="+", type=float, help="只绘制指定能量档")
    args = ap.parse_args(argv)

    with open(args.summary_json, encoding="utf-8") as fp:
        data = json.load(fp)

    # 按能量分组，每组取 vlsm_total 最大的为该能量最优
    from collections import defaultdict
    by_energy = defaultdict(list)
    for r in data:
        if args.filter_energy and r["energy"] not in args.filter_energy:
            continue
        by_energy[r["energy"]].append(r)

    energies = []
    vlsm_best = []
    det_best = []
    rank_best = []
    param_best = []
    for e in sorted(by_energy):
        attempts = by_energy[e]
        best = max(attempts, key=lambda x: x["vlsm_total"])
        energies.append(e)
        vlsm_best.append(best["vlsm_total"])
        det_best.append(best["detection_rate"] * 100)
        rank_best.append(best["rank"])
        param_best.append(f"α={best['alpha']:.2f}/mg={best['merge_gap']}")

    if not energies:
        print("无有效数据点", file=sys.stderr)
        return 1

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))

    # 左：能量 vs VLSM 数
    axes[0].plot(energies, vlsm_best, "o-", lw=1.5, markersize=6)
    axes[0].set_xlabel("POD energy target")
    axes[0].set_ylabel("VLSM count (108 frames)")
    axes[0].set_title("Energy vs VLSM detection")
    axes[0].grid(True, alpha=0.3)
    for i, (e, v, p) in enumerate(zip(energies, vlsm_best, param_best)):
        axes[0].annotate(f"{v}\n{p}", (e, v), fontsize=7, ha="center",
                         xytext=(0, 8), textcoords="offset points")

    # 中：能量 vs 检出率
    axes[1].plot(energies, det_best, "s-", lw=1.5, markersize=6, color="C1")
    axes[1].set_xlabel("POD energy target")
    axes[1].set_ylabel("Detection rate (%)")
    axes[1].set_title("Energy vs detection rate")
    axes[1].grid(True, alpha=0.3)
    axes[1].set_ylim([0, 105])
    for i, (e, d) in enumerate(zip(energies, det_best)):
        axes[1].annotate(f"{d:.1f}%", (e, d), fontsize=7, ha="center",
                         xytext=(0, 6), textcoords="offset points")

    # 右：能量 vs POD rank
    axes[2].semilogy(energies, rank_best, "d-", lw=1.5, markersize=6, color="C2")
    axes[2].set_xlabel("POD energy target")
    axes[2].set_ylabel("POD rank (log scale)")
    axes[2].set_title("Energy vs POD rank")
    axes[2].grid(True, alpha=0.3, which="both")
    for i, (e, r) in enumerate(zip(energies, rank_best)):
        axes[2].annotate(f"{r}", (e, r), fontsize=7, ha="left",
                         xytext=(4, 0), textcoords="offset points")

    fig.tight_layout()
    fig.savefig(args.out, dpi=150)
    print(f"[wrote] {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
