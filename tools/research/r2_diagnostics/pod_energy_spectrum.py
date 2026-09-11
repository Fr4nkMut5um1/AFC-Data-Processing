# -*- coding: utf-8 -*-
"""从 POD 基文件提取模态-能量占比数据，输出能量谱/累计能量曲线。

读取 tmp/pod_energy_sweep/pod_energy_sweep_basis.mat 的 eigenvalues,
输出每个能量档所需的 rank、每档模态能量占比、前 N 阶模态能量分布。

用法:
    python tools/research/r2_diagnostics/pod_energy_spectrum.py [--out tmp/pod_energy_series_opt/energy_curve.png]

依赖: numpy, matplotlib, h5py (读 -v7.3 .mat).
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[3]
BASIS = REPO / "tmp/pod_energy_sweep/pod_energy_sweep_basis.mat"


def load_eigenvalues(path=BASIS):
    """用 h5py 读 -v7.3 .mat (scipy 不支持 v7.3)."""
    import h5py
    with h5py.File(str(path), "r") as f:
        ev = np.array(f["denoise/eigenvalues"]).ravel()
        rank = int(np.array(f["denoise/rank"]).ravel()[0])
        n_spatial = int(np.array(f["denoise/n_spatial"]).ravel()[0])
        n_frames = int(np.array(f["denoise/frame_ids"]).ravel().size)
    return ev, rank, n_spatial, n_frames


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None, help="输出 PNG 路径")
    ap.add_argument("--json", default=None, help="输出数据 JSON 路径")
    ap.add_argument("--top", type=int, default=40, help="前 N 阶模态能量明细")
    args = ap.parse_args(argv)

    ev, rank, n_spatial, n_frames = load_eigenvalues()
    total = ev.sum()
    frac = ev / total
    cum = np.cumsum(frac)

    targets = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
    table = []
    for t in targets:
        idx = int(np.searchsorted(cum, t)) + 1
        idx = min(idx, rank)
        table.append({
            "energy_target": t,
            "rank": idx,
            "cumulative_energy": float(cum[idx - 1]),
            "first_mode_share_pct": float(frac[0] / cum[idx - 1] * 100) if idx and cum[idx - 1] > 0 else 0,
        })

    top_n = min(args.top, len(frac))
    detail = [{"mode": i + 1, "frac": float(frac[i]), "cum": float(cum[i])}
              for i in range(top_n)]

    out = {
        "n_eigenvalues": int(len(ev)),
        "rank": rank,
        "n_spatial": n_spatial,
        "n_frames": n_frames,
        "eigenvalue_sum": float(total),
        "top_mode_frac": float(frac[0]),
        "top10_cumsum": float(cum[9]) if len(ev) >= 10 else None,
        "targets": table,
        "detail": detail,
    }
    print(json.dumps(out, indent=2))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fp:
            json.dump(out, fp, indent=2)
        print(f"[wrote] {args.json}")

    if args.out:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(1, 2, figsize=(12, 4.5))
        axes[0].semilogy(np.arange(1, len(ev) + 1), ev, lw=0.8)
        axes[0].set_xlabel("Mode index"); axes[0].set_ylabel("eigenvalue (log)")
        axes[0].set_title("POD eigenvalue spectrum")
        axes[1].plot(np.arange(1, len(ev) + 1), cum * 100, lw=0.8)
        axes[1].axhline(50, color="gray", ls="--", lw=0.6)
        axes[1].axhline(80, color="gray", ls="--", lw=0.6)
        for t in targets:
            idx = int(np.searchsorted(cum, t)) + 1
            axes[1].annotate(f"{t:.0%}({idx})", (idx, t * 100),
                             fontsize=7, ha="left")
        axes[1].set_xlabel("Mode index")
        axes[1].set_ylabel("cumulative energy (%)")
        axes[1].set_title("Cumulative POD energy")
        fig.tight_layout()
        fig.savefig(args.out, dpi=150)
        print(f"[wrote] {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
