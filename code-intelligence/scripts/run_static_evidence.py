#!/usr/bin/env python3
"""Run the native collector in two independent MATLAB batch processes.

Standard library only; invokes MATLAB executable, never MATLAB Engine.
No scientific entrypoint is executed. No downloads or license setup.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


CASES = ("tandem_baseline_r2", "tandem_f40a3_phi0_r2")


def matlab_string(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matlab", default="matlab", help="MATLAB executable or full path")
    parser.add_argument("--case", choices=CASES, action="append", help="Default: both cases")
    parser.add_argument("--output", type=Path, help="New run directory will be created below this folder")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    executable = shutil.which(args.matlab)
    if executable is None:
        print("MATLAB executable not found; no native analysis was run. "
              "Use --matlab with an installed, licensed MATLAB executable.", file=sys.stderr)
        return 2
    output = (args.output or root / "code-intelligence/evidence/native").resolve()
    for case in CASES:
        if output == root / "cases" / "per_case" / case or root / "cases" / "per_case" / case in output.parents:
            parser.error("Evidence output must be outside scientific case directories")
    selected = list(dict.fromkeys(args.case or CASES))
    for case in selected:
        if not (root / "cases" / "per_case" / case / (case + "_case.m")).is_file():
            parser.error("Case entrypoint not found: " + case)
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="batch_", dir=output))
    summary = {"status": "RUNNING", "matlab_executable": executable,
               "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "scientific_entrypoint_requested": False, "cases": []}
    summary_path = run / "batch_summary.json"

    def save_summary():
        summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    save_summary()
    for case in selected:
        command = (
            "addpath(" + matlab_string(root / "code-intelligence/scripts") + ");"
            "collect_static_evidence(" + matlab_string(root / "cases" / "per_case" / case) + ","
            + matlab_string(run / case) + ");"
        )
        log = run / (case + ".log")
        record = {"case": case, "log": log.name, "status": "FAILED"}
        print("Collecting " + case + "; MATLAB log: " + str(log), flush=True)
        try:
            with log.open("wb") as stream:
                # shell=False: paths/expressions are passed as literal arguments.
                result = subprocess.run([executable, "-batch", command], cwd=root,
                                        stdout=stream, stderr=subprocess.STDOUT, check=False)
            record["returncode"] = result.returncode
            evidence = list((run / case).glob("*/execution_summary.json"))
            record["evidence_summaries"] = [str(p.relative_to(run)) for p in evidence]
            if result.returncode == 0 and len(evidence) == 1:
                native = json.loads(evidence[0].read_text(encoding="utf-8"))
                if native.get("status") == "COMPLETE_WITH_LIMITATIONS":
                    record["status"] = "COMPLETE_WITH_LIMITATIONS"
        except (OSError, ValueError) as error:
            record["error"] = str(error)
        summary["cases"].append(record)
        save_summary()
    complete = all(x["status"] == "COMPLETE_WITH_LIMITATIONS" for x in summary["cases"])
    summary["status"] = "COMPLETE_WITH_LIMITATIONS" if complete else "FAILED_OR_PARTIAL"
    save_summary()
    print("Batch status: " + summary["status"] + "; evidence: " + str(run))
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
