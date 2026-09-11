# -*- coding: utf-8 -*-
"""从 attempt manifest 与生成日志汇总 VLSM 统计。

用法:
    python tools/research/r2_diagnostics/summarize_attempts.py <attempt_dir_or_parent> [...]

输出表格：attempt_id | energy | rank | params | vlsm_total | detection_rate | frame_consistency
"""
import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GOLD_MANIFEST = REPO / "tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01/manifest.json"


def load_gold_frames():
    """加载金标准 attempt_c4_01 三轮 frame_ids."""
    if not GOLD_MANIFEST.is_file():
        return {}
    with open(GOLD_MANIFEST, encoding="utf-8") as fp:
        m = json.load(fp)
    return {int(r["round"]): [int(x) for x in r["frame_ids"]] for r in m["rounds"]}


def check_frame_consistency(manifest_path, gold_rounds):
    """检查帧序列一致性，返回 OK/FAIL/SKIP."""
    if not gold_rounds:
        return "SKIP"
    with open(manifest_path, encoding="utf-8") as fp:
        m = json.load(fp)
    rounds = {int(r["round"]): [int(x) for x in r["frame_ids"]] for r in m["rounds"]}
    for rr, gold_ids in gold_rounds.items():
        got = rounds.get(rr)
        if got != gold_ids:
            return "FAIL"
    return "OK"


def summarize_attempt(attempt_dir, gold_rounds):
    """从 manifest.json 提取关键统计."""
    mp = Path(attempt_dir) / "manifest.json"
    if not mp.is_file():
        return None
    with open(mp, encoding="utf-8") as fp:
        m = json.load(fp)
    p = m["parameters"]
    vlsm_tot = sum(r["total_cluster_vlsm"] for r in m["rounds"])
    det_tot = sum(r["frames_with_cluster_vlsm"] for r in m["rounds"])
    n_frames = sum(r["n_frames"] for r in m["rounds"])
    consist = check_frame_consistency(mp, gold_rounds)
    return {
        "attempt_dir": str(attempt_dir),
        "attempt_id": int(m["attempt_id"]),
        "energy": float(m["energy_target"]),
        "rank": int(m["pod_rank"]),
        "cumulative_energy": float(m.get("cumulative_energy", 0)),
        "connectivity": int(p["connectivity"]),
        "alpha": float(p["alpha"]),
        "seed_alpha": float(p["seed_alpha"]),
        "merge_gap": int(p["merge_gap_cells"]),
        "vlsm_total": vlsm_tot,
        "detection_frames": det_tot,
        "n_frames": n_frames,
        "detection_rate": det_tot / n_frames if n_frames else 0,
        "frame_consistency": consist,
    }


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", help="attempt 目录或父目录")
    ap.add_argument("--json", default=None, help="输出 JSON 路径")
    args = ap.parse_args(argv)

    gold_rounds = load_gold_frames()
    results = []
    for p in args.paths:
        pp = Path(p)
        if not pp.exists():
            print(f"[skip] {p}: 不存在", file=sys.stderr)
            continue
        if (pp / "manifest.json").is_file():
            # 单个 attempt 目录
            res = summarize_attempt(pp, gold_rounds)
            if res:
                results.append(res)
        else:
            # 父目录，扫描 attempt_* 子目录
            for sub in sorted(pp.glob("attempt_*")):
                if sub.is_dir() and (sub / "manifest.json").is_file():
                    res = summarize_attempt(sub, gold_rounds)
                    if res:
                        results.append(res)

    if not results:
        print("未找到任何有效 attempt manifest", file=sys.stderr)
        return 1

    results.sort(key=lambda x: (x["energy"], x["attempt_id"]))

    # 终端表格输出
    print(f"{'ID':>3} {'E%':>4} {'rank':>5} {'conn':>4} {'α':>5} {'sα':>5} {'mg':>3} "
          f"{'VLSM':>5} {'det':>4} {'rate%':>5} {'frm':>4}")
    print("-" * 72)
    for r in results:
        print(f"{r['attempt_id']:>3} {r['energy']*100:>4.0f} {r['rank']:>5} "
              f"{r['connectivity']:>4} {r['alpha']:>5.2f} {r['seed_alpha']:>5.2f} "
              f"{r['merge_gap']:>3} {r['vlsm_total']:>5} "
              f"{r['detection_frames']:>4} {r['detection_rate']*100:>5.1f} "
              f"{r['frame_consistency']:>4}")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fp:
            json.dump(results, fp, indent=2)
        print(f"\n[wrote] {args.json}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
