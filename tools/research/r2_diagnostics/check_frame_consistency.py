# -*- coding: utf-8 -*-
"""帧序列一致性核对：POD 能量系列 attempt 与金标准 attempt_c4_01 逐轮比对。

用法:
    python tools/research/r2_diagnostics/check_frame_consistency.py <attempt_dir> [<attempt_dir> ...]

金标准: tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01 (attempt_id=17,
random_seed=20260828, 三轮 Round 种子 20276828/29/30)。所有能量、所有参数组合
必须与其三轮 frame_ids 完全一致, 否则跨能量对比不可比。
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GOLD = REPO / "tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01/manifest.json"


def load_rounds(manifest_path):
    with open(manifest_path, encoding="utf-8") as fp:
        m = json.load(fp)
    rounds = {int(r["round"]): [int(x) for x in r["frame_ids"]] for r in m["rounds"]}
    return m, rounds


def main(argv):
    if not GOLD.is_file():
        print(f"FATAL: 金标准 manifest 不存在: {GOLD}")
        return 2
    gold_manifest, gold_rounds = load_rounds(GOLD)
    print(f"金标准: attempt_id={gold_manifest['attempt_id']} "
          f"seed={gold_manifest['random_seed']:.0f} rounds={sorted(gold_rounds)}")

    targets = argv[1:]
    if not targets:
        print("用法: check_frame_consistency.py <attempt_dir> [...]")
        return 2

    n_fail = 0
    for t in targets:
        mp = Path(t) / "manifest.json"
        if not mp.is_file():
            print(f"[FAIL] {t}: 缺少 manifest.json")
            n_fail += 1
            continue
        m, rounds = load_rounds(mp)
        ok = True
        for rr, gold_ids in gold_rounds.items():
            got = rounds.get(rr)
            if got != gold_ids:
                ok = False
                diff = "缺失该轮" if got is None else (
                    f"n={len(got)} vs {len(gold_ids)}, "
                    f"首个差异位 {next((i for i, (a, b) in enumerate(zip(got, gold_ids)) if a != b), 'len')}")
                print(f"[FAIL] {t} round {rr}: frame_ids 不一致 ({diff})")
        expect_seed = 20276828 - 1000 * (int(m["attempt_id"]) - 1)
        if int(m["random_seed"]) != expect_seed:
            ok = False
            print(f"[FAIL] {t}: random_seed={m['random_seed']:.0f} != 期望 {expect_seed} "
                  f"(attempt_id={m['attempt_id']})")
        if ok:
            print(f"[OK]   {t}: attempt_id={m['attempt_id']} E={m['energy_target']:.0%} "
                  f"rank={m['pod_rank']} 三轮 frame_ids 与金标准一致")
        else:
            n_fail += 1
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
