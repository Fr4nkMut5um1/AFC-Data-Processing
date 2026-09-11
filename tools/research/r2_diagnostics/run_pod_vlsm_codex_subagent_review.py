#!/usr/bin/env python3
"""Review POD fields with isolated official GPT-5.6-SOL Codex subagents."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any


MODEL = "gpt-5.6-sol"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attempt-dir", type=Path, required=True)
    parser.add_argument("--round", type=int, required=True, dest="round_id")
    parser.add_argument("--batch-size", type=int, default=6)
    parser.add_argument("--max-workers", type=int, default=3)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
    os.replace(tmp, path)


def delta_text(samples: list[dict[str, Any]]) -> str:
    return "; ".join(
        f"x={float(row['x_mm']):.1f} mm: 3delta99={float(row['three_delta99_mm']):.1f} mm"
        for row in samples
    )


def prompt_for_batch(
    frame_ids: list[int], fov: dict[str, Any], samples: list[dict[str, Any]]
) -> str:
    return (
        "Directly inspect the attached pure POD contourf images with your native vision. "
        "Do not call external vision APIs or inspect cluster_frames. Each image title contains "
        "its frame id. Red is positive streamwise fluctuation, blue is negative, and white is "
        "near zero. Axes are millimetres. Identify only coherent, same-sign, streamwise-elongated "
        "bands whose visible x length is approximately at least the local 3delta99 reference; "
        "do not count short round lobes or scattered fragments. FOV-edge structures must be kept "
        "and marked touches_fov_edge=true. Estimate sign, x/y bounding range, and visible x length. "
        "This is an operational 2C-2D XOY review, not 3-D truth. If a frame has no VLSM, return an "
        "empty objects array. Return exactly one frame record for every expected id. "
        f"Expected frame ids in attachment order: {frame_ids}. "
        f"FOV x=[{float(fov['x_min_mm']):.2f},{float(fov['x_max_mm']):.2f}] mm, "
        f"y=[{float(fov['y_min_mm']):.2f},{float(fov['y_max_mm']):.2f}] mm. "
        f"Length references: {delta_text(samples)}. "
        "Use model='gpt-5.6-sol'. Notes may be concise Chinese."
    )


def validate_raw(
    value: dict[str, Any], expected_ids: list[int], fov: dict[str, Any]
) -> list[dict[str, Any]]:
    if value.get("model") != MODEL:
        raise ValueError("subagent did not attest gpt-5.6-sol")
    frames = value.get("frames")
    if not isinstance(frames, list):
        raise ValueError("frames is not an array")
    by_id = {int(row["frame_id"]): row for row in frames}
    if set(by_id) != set(expected_ids):
        raise ValueError(f"frame ids differ: got {sorted(by_id)}, expected {expected_ids}")
    normalized = []
    width = float(fov["width_mm"])
    height = float(fov["height_mm"])
    for frame_id in expected_ids:
        row = by_id[frame_id]
        objects = []
        for index, obj in enumerate(row.get("objects", []), start=1):
            sign = str(obj["sign"]).lower()
            if sign not in {"positive", "negative"}:
                raise ValueError(f"invalid sign in frame {frame_id}")
            numeric_names = [
                "x_min_mm_est", "x_max_mm_est", "y_min_mm_est",
                "y_max_mm_est", "length_x_mm_est", "confidence",
            ]
            numbers = {name: float(obj[name]) for name in numeric_names}
            if not all(math.isfinite(number) for number in numbers.values()):
                raise ValueError(f"non-finite geometry in frame {frame_id}")
            if numbers["x_max_mm_est"] <= numbers["x_min_mm_est"]:
                raise ValueError(f"invalid x range in frame {frame_id}")
            if numbers["y_max_mm_est"] <= numbers["y_min_mm_est"]:
                raise ValueError(f"invalid y range in frame {frame_id}")
            x_min = max(float(fov["x_min_mm"]), numbers["x_min_mm_est"])
            x_max = min(float(fov["x_max_mm"]), numbers["x_max_mm_est"])
            y_min = max(float(fov["y_min_mm"]), numbers["y_min_mm_est"])
            y_max = min(float(fov["y_max_mm"]), numbers["y_max_mm_est"])
            edge = bool(obj["touches_fov_edge"]) or (
                x_min <= float(fov["x_min_mm"]) + 0.02 * width
                or x_max >= float(fov["x_max_mm"]) - 0.02 * width
                or y_min <= float(fov["y_min_mm"]) + 0.02 * height
                or y_max >= float(fov["y_max_mm"]) - 0.02 * height
            )
            objects.append(
                {
                    "vision_id": index,
                    "sign": sign,
                    "x_min_mm_est": x_min,
                    "x_max_mm_est": x_max,
                    "y_min_mm_est": y_min,
                    "y_max_mm_est": y_max,
                    "centroid_x_mm_est": 0.5 * (x_min + x_max),
                    "centroid_y_mm_est": 0.5 * (y_min + y_max),
                    "length_x_mm_est": numbers["length_x_mm_est"],
                    "touches_fov_edge": edge,
                    "confidence": min(1.0, max(0.0, numbers["confidence"])),
                    "notes": str(obj.get("notes", "")),
                }
            )
        normalized.append(
            {
                "frame_id": frame_id,
                "has_vlsm": bool(objects),
                "objects": objects,
                "overall_confidence": min(
                    1.0, max(0.0, float(row.get("overall_confidence", 0.5)))
                ),
                "notes": str(row.get("notes", "")),
                "vision_model": MODEL,
            }
        )
    return normalized


def run_batch(
    batch_index: int,
    images: list[Path],
    frame_ids: list[int],
    context: dict[str, Any],
    output_dir: Path,
    schema_file: Path,
    repo_root: Path,
    retries: int,
    force: bool,
) -> tuple[int, list[dict[str, Any]] | None, str | None]:
    output_file = output_dir / f"batch_{batch_index:02d}.json"
    log_file = output_dir / f"batch_{batch_index:02d}.log"
    if output_file.is_file() and not force:
        try:
            return batch_index, validate_raw(read_json(output_file), frame_ids, context["fov"]), None
        except Exception:
            pass
    prompt = prompt_for_batch(frame_ids, context["fov"], context["delta99_samples"])
    # Put the positional prompt immediately after ``exec``.  The variadic
    # ``-i/--image`` option can otherwise consume the prompt as one more image
    # path, making Codex fall back to an empty stdin prompt.
    command = ["codex", "exec", prompt,
        "--ignore-user-config", "--ephemeral", "-m", MODEL,
        "-s", "read-only", "-C", str(repo_root),
        "--output-schema", str(schema_file), "-o", str(output_file)]
    for image in images:
        command.extend(["-i", str(image)])
    command.append(prompt)
    last_error = "unknown error"
    for attempt in range(1, retries + 1):
        completed = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=600,
        )
        log_file.write_text(completed.stdout, encoding="utf-8")
        try:
            if completed.returncode != 0:
                raise RuntimeError(f"codex exec exited {completed.returncode}")
            frames = validate_raw(read_json(output_file), frame_ids, context["fov"])
            return batch_index, frames, None
        except Exception as exc:
            last_error = f"attempt {attempt}/{retries}: {type(exc).__name__}: {exc}"
            if attempt < retries:
                time.sleep(3 * attempt)
    return batch_index, None, last_error


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent.parent
    schema_file = script_dir / "codex_vlsm_review_schema.json"
    attempt_dir = args.attempt_dir.resolve()
    round_dir = attempt_dir / f"round_{args.round_id:02d}"
    context = read_json(round_dir / f"round_{args.round_id:02d}_visual_context.json")
    images = [Path(value).resolve() for value in context["pure_images"]]
    frame_ids = [int(value) for value in context["frame_ids"]]
    batches = []
    for start in range(0, len(images), args.batch_size):
        batches.append((images[start : start + args.batch_size], frame_ids[start : start + args.batch_size]))
    output_dir = round_dir / "codex_gpt56sol_subagents"
    output_dir.mkdir(parents=True, exist_ok=True)
    print(
        f"Round {args.round_id:02d}: {len(batches)} isolated official {MODEL} subagents",
        flush=True,
    )
    results: dict[int, list[dict[str, Any]]] = {}
    failures: dict[int, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as pool:
        futures = {
            pool.submit(
                run_batch, index, batch_images, batch_ids, context, output_dir,
                schema_file, repo_root, args.retries, args.force,
            ): index
            for index, (batch_images, batch_ids) in enumerate(batches, start=1)
        }
        for future in concurrent.futures.as_completed(futures):
            index, frames, error = future.result()
            if frames is None:
                failures[index] = error or "unknown error"
                print(f"  batch {index:02d}: FAILED", flush=True)
            else:
                results[index] = frames
                print(f"  batch {index:02d}: {len(frames)} frames", flush=True)
    ordered_frames = [frame for index in sorted(results) for frame in results[index]]
    compiled = {
        "schema_version": 1,
        "status": "complete" if not failures and len(ordered_frames) == len(frame_ids) else "incomplete",
        "reviewer": "isolated official Codex GPT-5.6-SOL subagents",
        "vision_model": MODEL,
        "provider_isolation": "--ignore-user-config (official openai via ChatGPT login)",
        "method": "Blind native-vision review of pure POD contourf images in six-frame batches.",
        "round": args.round_id,
        "round_frame_ids": frame_ids,
        "frames": ordered_frames,
        "failures": [
            {"batch": index, "error": failures[index]} for index in sorted(failures)
        ],
        "summary": {
            "reviewed_frames": len(ordered_frames),
            "frames_with_visual_vlsm": sum(bool(row["objects"]) for row in ordered_frames),
            "total_visual_vlsm": sum(len(row["objects"]) for row in ordered_frames),
            "mean_overall_confidence": (
                sum(row["overall_confidence"] for row in ordered_frames) / len(ordered_frames)
                if ordered_frames else 0.0
            ),
        },
    }
    review_file = round_dir / f"round_{args.round_id:02d}_visual_review.json"
    write_json(review_file, compiled)
    write_json(round_dir / "subagent_gpt56sol_audit.json", compiled)
    print(f"Saved {review_file}", flush=True)
    return 0 if compiled["status"] == "complete" else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Codex subagent review failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
