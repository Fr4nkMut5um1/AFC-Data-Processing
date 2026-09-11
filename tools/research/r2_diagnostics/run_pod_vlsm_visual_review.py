#!/usr/bin/env python3
"""Run blind, per-frame GPT-5.6-SOL review for POD VLSM acceptance."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any


DEFAULT_VISION_DIR = Path(r"C:\Users\Frank_7840HSw\.codex\skills\claude-vision-skill")
REQUIRED_MODEL = "gpt-5.6-sol"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attempt-dir", type=Path, required=True)
    parser.add_argument("--round", type=int, required=True, dest="round_id")
    parser.add_argument("--max-workers", type=int, default=3)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--vision-dir", type=Path, default=DEFAULT_VISION_DIR)
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


def configured_model(env_file: Path) -> str:
    if not env_file.is_file():
        raise FileNotFoundError(f"Vision configuration is missing: {env_file}")
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("VISION_MODEL="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("VISION_MODEL is missing from the vision configuration")


def delta_description(samples: list[dict[str, Any]]) -> str:
    parts = []
    for sample in samples:
        parts.append(
            f"x={float(sample['x_mm']):.1f}: "
            f"delta99={float(sample['delta99_mm']):.1f}, "
            f"3delta99={float(sample['three_delta99_mm']):.1f} mm"
        )
    return "; ".join(parts)


def build_prompt(
    frame_id: int,
    fov: dict[str, Any],
    delta_samples: list[dict[str, Any]],
) -> str:
    schema = {
        "frame_id": frame_id,
        "has_vlsm": True,
        "objects": [
            {
                "vision_id": 1,
                "sign": "positive|negative",
                "x_min_mm_est": 0.0,
                "x_max_mm_est": 0.0,
                "y_min_mm_est": 0.0,
                "y_max_mm_est": 0.0,
                "length_x_mm_est": 0.0,
                "touches_fov_edge": False,
                "confidence": 0.0,
                "notes": "中文简述视觉依据",
            }
        ],
        "overall_confidence": 0.0,
        "notes": "中文说明不确定性；无结构时说明原因",
    }
    return (
        "你是独立的二维POD流场VLSM视觉审核员。只根据这张纯场图判断，不得假设或猜测"
        "聚类算法的结果。图中色标为流向脉动速度u'：红色为正脉动，蓝色为负脉动，白色"
        "接近零；坐标轴单位均为mm。请识别流向上连续或视觉上属于同一主体、同号、细长的"
        "脉动带。操作性VLSM判据是可见流向长度大致达到当地3倍delta99；短小、近圆形或"
        "只有零散色块的区域不要计入。图像/FOV边缘不做剔除：结构触边时按可见部分识别，"
        "并将touches_fov_edge设为true。这里仅判断2C-2D XOY平面连通结构，不代表三维真值。\n"
        f"当前帧号：{frame_id}。FOV范围：x=[{float(fov['x_min_mm']):.2f}, "
        f"{float(fov['x_max_mm']):.2f}] mm，y=[{float(fov['y_min_mm']):.2f}, "
        f"{float(fov['y_max_mm']):.2f}] mm。delta99参考："
        f"{delta_description(delta_samples)}。\n"
        "请从坐标刻度估计每个VLSM的正负号、x/y包围范围和流向长度。不要把标题、坐标轴或"
        "colorbar当成结构。若没有VLSM，has_vlsm=false且objects=[]。只输出一个合法JSON对象，"
        "不要使用Markdown代码块，不要输出JSON以外的文字。必须使用如下字段：\n"
        + json.dumps(schema, ensure_ascii=False)
    )


def extract_json(text: str) -> dict[str, Any]:
    cleaned = re.sub(r"^\s*```(?:json)?\s*", "", text.strip(), flags=re.I)
    cleaned = re.sub(r"\s*```\s*$", "", cleaned)
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end < start:
        raise ValueError("Vision response does not contain a JSON object")
    value = json.loads(cleaned[start : end + 1])
    if not isinstance(value, dict):
        raise ValueError("Vision response root is not an object")
    return value


def finite_number(value: Any, field: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field} is not numeric") from exc
    if not math.isfinite(number):
        raise ValueError(f"{field} is not finite")
    return number


def normalize_review(
    raw: dict[str, Any], frame_id: int, fov: dict[str, Any]
) -> dict[str, Any]:
    width = float(fov["width_mm"])
    height = float(fov["height_mm"])
    x_pad = 0.03 * width
    y_pad = 0.03 * height
    normalized: list[dict[str, Any]] = []
    objects = raw.get("objects", [])
    if not isinstance(objects, list):
        raise ValueError("objects is not a list")
    for idx, obj in enumerate(objects, start=1):
        if not isinstance(obj, dict):
            raise ValueError("an object entry is not a JSON object")
        sign = str(obj.get("sign", "")).strip().lower()
        if sign not in {"positive", "negative"}:
            raise ValueError(f"object {idx} has invalid sign: {sign!r}")
        x_min = finite_number(obj.get("x_min_mm_est"), "x_min_mm_est")
        x_max = finite_number(obj.get("x_max_mm_est"), "x_max_mm_est")
        y_min = finite_number(obj.get("y_min_mm_est"), "y_min_mm_est")
        y_max = finite_number(obj.get("y_max_mm_est"), "y_max_mm_est")
        if x_max <= x_min or y_max <= y_min:
            raise ValueError(f"object {idx} has a degenerate bounding box")
        if (
            x_min < float(fov["x_min_mm"]) - x_pad
            or x_max > float(fov["x_max_mm"]) + x_pad
            or y_min < float(fov["y_min_mm"]) - y_pad
            or y_max > float(fov["y_max_mm"]) + y_pad
        ):
            raise ValueError(f"object {idx} lies outside the plotted FOV")
        x_min = max(float(fov["x_min_mm"]), x_min)
        x_max = min(float(fov["x_max_mm"]), x_max)
        y_min = max(float(fov["y_min_mm"]), y_min)
        y_max = min(float(fov["y_max_mm"]), y_max)
        length = finite_number(obj.get("length_x_mm_est", x_max - x_min), "length")
        if length <= 0:
            length = x_max - x_min
        confidence = finite_number(obj.get("confidence", 0.5), "confidence")
        confidence = min(1.0, max(0.0, confidence))
        edge_tol_x = max(0.02 * width, 1e-9)
        edge_tol_y = max(0.02 * height, 1e-9)
        geometric_edge = (
            x_min <= float(fov["x_min_mm"]) + edge_tol_x
            or x_max >= float(fov["x_max_mm"]) - edge_tol_x
            or y_min <= float(fov["y_min_mm"]) + edge_tol_y
            or y_max >= float(fov["y_max_mm"]) - edge_tol_y
        )
        normalized.append(
            {
                "vision_id": idx,
                "sign": sign,
                "x_min_mm_est": x_min,
                "x_max_mm_est": x_max,
                "y_min_mm_est": y_min,
                "y_max_mm_est": y_max,
                "centroid_x_mm_est": 0.5 * (x_min + x_max),
                "centroid_y_mm_est": 0.5 * (y_min + y_max),
                "length_x_mm_est": length,
                "touches_fov_edge": bool(obj.get("touches_fov_edge", False))
                or geometric_edge,
                "confidence": confidence,
                "notes": str(obj.get("notes", "")).strip(),
            }
        )
    overall = raw.get("overall_confidence", 0.5 if normalized else 0.6)
    overall_confidence = min(1.0, max(0.0, finite_number(overall, "overall_confidence")))
    return {
        "frame_id": frame_id,
        "has_vlsm": bool(normalized),
        "objects": normalized,
        "overall_confidence": overall_confidence,
        "notes": str(raw.get("notes", "")).strip(),
    }


def review_one(
    image_path: Path,
    frame_id: int,
    fov: dict[str, Any],
    delta_samples: list[dict[str, Any]],
    output_dir: Path,
    vision_script: Path,
    retries: int,
    timeout_seconds: int,
    force: bool,
) -> tuple[int, dict[str, Any] | None, str | None]:
    json_file = output_dir / f"frame_{frame_id:06d}.json"
    raw_file = output_dir / f"frame_{frame_id:06d}_raw.txt"
    if json_file.is_file() and not force:
        try:
            return frame_id, read_json(json_file), None
        except (OSError, ValueError, json.JSONDecodeError):
            pass
    prompt = build_prompt(frame_id, fov, delta_samples)
    last_error = "unknown error"
    for attempt in range(1, retries + 1):
        try:
            completed = subprocess.run(
                ["node", str(vision_script), str(image_path), prompt],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout_seconds,
            )
            raw_file.write_text(completed.stdout, encoding="utf-8")
            if completed.returncode != 0:
                raise RuntimeError(
                    f"vision.js exited {completed.returncode}: "
                    f"{completed.stderr.strip()[:300]}"
                )
            review = normalize_review(extract_json(completed.stdout), frame_id, fov)
            review["image_path"] = str(image_path.resolve())
            review["vision_model"] = REQUIRED_MODEL
            review["prompt_sha256"] = hashlib.sha256(prompt.encode("utf-8")).hexdigest()
            write_json(json_file, review)
            return frame_id, review, None
        except Exception as exc:  # Each failure is preserved and retried.
            last_error = f"attempt {attempt}/{retries}: {type(exc).__name__}: {exc}"
            (output_dir / f"frame_{frame_id:06d}_error.txt").write_text(
                last_error + "\n", encoding="utf-8"
            )
            if attempt < retries:
                time.sleep(min(2**attempt, 8))
    return frame_id, None, last_error


def frame_id_from_path(path: Path) -> int:
    match = re.search(r"frame_(\d+)\.png$", path.name)
    if not match:
        raise ValueError(f"Cannot extract frame id from {path}")
    return int(match.group(1))


def main() -> int:
    args = parse_args()
    attempt_dir = args.attempt_dir.resolve()
    round_dir = attempt_dir / f"round_{args.round_id:02d}"
    context_file = round_dir / f"round_{args.round_id:02d}_visual_context.json"
    context = read_json(context_file)
    vision_script = args.vision_dir.resolve() / "vision.js"
    model = configured_model(args.vision_dir.resolve() / ".env")
    if model != REQUIRED_MODEL:
        raise RuntimeError(
            f"Refusing visual review: VISION_MODEL={model!r}, required {REQUIRED_MODEL!r}"
        )
    if not vision_script.is_file():
        raise FileNotFoundError(f"Vision script is missing: {vision_script}")

    images = [Path(value).resolve() for value in context["pure_images"]]
    expected_ids = [int(value) for value in context["frame_ids"]]
    actual_ids = [frame_id_from_path(path) for path in images]
    if actual_ids != expected_ids:
        raise RuntimeError("Visual context image order does not match frame_ids")
    missing_images = [str(path) for path in images if not path.is_file()]
    if missing_images:
        raise FileNotFoundError(f"Missing pure field images: {missing_images[:3]}")

    output_dir = round_dir / "visual_reviews"
    output_dir.mkdir(parents=True, exist_ok=True)
    print(
        f"Round {args.round_id:02d}: reviewing {len(images)} blind fields with "
        f"{REQUIRED_MODEL} ({args.max_workers} workers)",
        flush=True,
    )
    results: dict[int, dict[str, Any]] = {}
    failures: dict[int, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as pool:
        futures = {
            pool.submit(
                review_one,
                image,
                frame_id,
                context["fov"],
                context["delta99_samples"],
                output_dir,
                vision_script,
                args.retries,
                args.timeout_seconds,
                args.force,
            ): frame_id
            for image, frame_id in zip(images, expected_ids)
        }
        for future in concurrent.futures.as_completed(futures):
            frame_id, review, error = future.result()
            if review is None:
                failures[frame_id] = error or "unknown error"
                print(f"  frame {frame_id}: FAILED", flush=True)
            else:
                results[frame_id] = review
                print(
                    f"  frame {frame_id}: {len(review['objects'])} visual VLSM",
                    flush=True,
                )

    ordered = [results[frame_id] for frame_id in expected_ids if frame_id in results]
    compiled = {
        "schema_version": 1,
        "status": "complete" if not failures else "incomplete",
        "reviewer": "blind Codex visual review",
        "vision_model": REQUIRED_MODEL,
        "method": (
            "Independent per-frame review of pure POD contourf fields; cluster overlays "
            "were not provided to the vision model. Operational 2C-2D comparison only."
        ),
        "round": args.round_id,
        "round_frame_ids": expected_ids,
        "frames": ordered,
        "failures": [
            {"frame_id": frame_id, "error": failures[frame_id]}
            for frame_id in sorted(failures)
        ],
        "summary": {
            "reviewed_frames": len(ordered),
            "frames_with_visual_vlsm": sum(bool(row["objects"]) for row in ordered),
            "total_visual_vlsm": sum(len(row["objects"]) for row in ordered),
            "mean_overall_confidence": (
                sum(float(row["overall_confidence"]) for row in ordered) / len(ordered)
                if ordered
                else 0.0
            ),
        },
    }
    review_file = round_dir / f"round_{args.round_id:02d}_visual_review.json"
    write_json(review_file, compiled)
    print(f"Saved {review_file}", flush=True)
    return 0 if not failures else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"visual review failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
