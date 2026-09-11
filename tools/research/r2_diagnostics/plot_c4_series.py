# -*- coding: utf-8 -*-
"""50% 能量系列 c4_01~08 参数寻优过程可视化。

从 tmp/pod_vlsm_parameter_acceptance_36x3/ 读取 attempt_17-25 (c4系列)，
绘制参数寻优轨迹：merge_gap → alpha → seed_alpha 逐步调优的 VLSM 增长曲线。
作为其他能量档寻优的参考基准。
"""
import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BASE = REPO / "tmp/pod_vlsm_parameter_acceptance_36x3"

# c4 系列映射 (attempt_id: 标签)
C4_SERIES = {
    17: "c4_01 基准 α0.40/mg0",
    18: "c4_02 mg4",
    20: "c4_03 mg8",
    21: "c4_04 mg12",
    22: "c4_05 mg16",
    23: "c4_06 α0.35/mg12",
    24: "c4_07 α0.35/sα0.55",
    25: "c4_08 最优 α0.30/sα0.55",
}


def load_c4_series():
    results = []
    for aid, label in C4_SERIES.items():
        mp = BASE / f"attempt_{aid:02d}/manifest.json"
        if not mp.is_file():
            continue
        with open(mp, encoding="utf-8") as fp:
            m = json.load(fp)
        p = m["parameters"]
        vlsm = sum(r["total_cluster_vlsm"] for r in m["rounds"])
        det = sum(r["frames_with_cluster_vlsm"] for r in m["rounds"])
        results.append({
            "attempt_id": aid,
            "label": label,
            "alpha": p["alpha"],
            "seed_alpha": p["seed_alpha"],
            "merge_gap": p["merge_gap_cells"],
            "vlsm": vlsm,
            "detection": det,
            "detection_rate": det / 108,
        })
    results.sort(key=lambda x: x["attempt_id"])
    return results


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="c4_series_trajectory.png")
    args = ap.parse_args(argv)

    data = load_c4_series()
    if not data:
        print("未找到 c4 系列数据", file=sys.stderr)
        return 1

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # 左上：VLSM 数随 attempt_id 增长
    x = [d["attempt_id"] for d in data]
    y = [d["vlsm"] for d in data]
    axes[0, 0].plot(x, y, "o-", lw=1.5, markersize=7)
    axes[0, 0].set_xlabel("attempt_id")
    axes[0, 0].set_ylabel("VLSM count (108 frames)")
    axes[0, 0].set_title("c4 series: VLSM growth trajectory")
    axes[0, 0].grid(True, alpha=0.3)
    for i, (aid, v, lbl) in enumerate(zip(x, y, [d["label"] for d in data])):
        axes[0, 0].annotate(f"{v}", (aid, v), fontsize=8, ha="left",
                            xytext=(4, 2), textcoords="offset points")

    # 右上：检出率
    y2 = [d["detection_rate"] * 100 for d in data]
    axes[0, 1].plot(x, y2, "s-", lw=1.5, markersize=6, color="C1")
    axes[0, 1].set_xlabel("attempt_id")
    axes[0, 1].set_ylabel("Detection rate (%)")
    axes[0, 1].set_title("c4 series: detection rate")
    axes[0, 1].grid(True, alpha=0.3)
    axes[0, 1].set_ylim([65, 102])

    # 左下：参数空间 (alpha vs merge_gap, 点大小=VLSM)
    alphas = [d["alpha"] for d in data]
    mgs = [d["merge_gap"] for d in data]
    sizes = [(d["vlsm"] - 90) * 3 for d in data]  # 缩放以可见
    axes[1, 0].scatter(alphas, mgs, s=sizes, alpha=0.6, c=y, cmap="viridis")
    axes[1, 0].set_xlabel("alpha")
    axes[1, 0].set_ylabel("merge_gap_cells")
    axes[1, 0].set_title("Parameter space (size=VLSM, color=VLSM)")
    axes[1, 0].grid(True, alpha=0.3)
    for d in data:
        axes[1, 0].annotate(f"c4_{d['attempt_id']-16:02d}", (d["alpha"], d["merge_gap"]),
                            fontsize=7, ha="center")

    # 右下：表格文本
    axes[1, 1].axis("off")
    table_text = "attempt | α    | sα   | mg | VLSM | det%\n" + "-" * 45 + "\n"
    for d in data:
        table_text += f"{d['attempt_id']:>7} | {d['alpha']:.2f} | {d['seed_alpha']:.2f} | " \
                      f"{d['merge_gap']:>2} | {d['vlsm']:>4} | {d['detection_rate']*100:>4.1f}\n"
    axes[1, 1].text(0.1, 0.9, table_text, fontsize=9, family="monospace",
                    verticalalignment="top", transform=axes[1, 1].transAxes)

    fig.tight_layout()
    fig.savefig(args.out, dpi=150)
    print(f"[wrote] {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
