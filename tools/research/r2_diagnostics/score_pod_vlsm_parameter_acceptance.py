#!/usr/bin/env python3
"""Score object-level POD VLSM agreement and write auditable reports."""

from __future__ import annotations

import argparse
from functools import lru_cache
import json
import math
import os
from pathlib import Path
import statistics
import sys
from typing import Any, Iterable


THRESHOLDS = {
    "object_f1_min": 0.80,
    "sign_accuracy_min": 0.90,
    "streamwise_iou_median_min": 0.65,
    "length_relative_error_median_max": 0.20,
    "position_match_rate_min": 0.85,
    "edge_object_f1_min": 0.80,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attempt-dir", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
    os.replace(tmp, path)


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and not value:
        return []
    return [value]


def safe_div(numerator: float, denominator: float, empty_value: float = 1.0) -> float:
    return numerator / denominator if denominator else empty_value


def median_or_none(values: Iterable[float]) -> float | None:
    data = list(values)
    return statistics.median(data) if data else None


def percentile(values: Iterable[float], fraction: float) -> float | None:
    data = sorted(values)
    if not data:
        return None
    if len(data) == 1:
        return data[0]
    position = fraction * (len(data) - 1)
    low = math.floor(position)
    high = math.ceil(position)
    if low == high:
        return data[low]
    weight = position - low
    return data[low] * (1 - weight) + data[high] * weight


def interval_iou(a0: float, a1: float, b0: float, b1: float) -> float:
    intersection = max(0.0, min(a1, b1) - max(a0, b0))
    union = max(a1, b1) - min(a0, b0)
    return safe_div(intersection, union, 0.0)


def bbox_iou(cluster: dict[str, Any], vision: dict[str, Any]) -> float:
    ax0, ax1 = float(cluster["x_min_mm"]), float(cluster["x_max_mm"])
    ay0, ay1 = float(cluster["y_min_mm"]), float(cluster["y_max_mm"])
    bx0, bx1 = float(vision["x_min_mm_est"]), float(vision["x_max_mm_est"])
    by0, by1 = float(vision["y_min_mm_est"]), float(vision["y_max_mm_est"])
    intersection = max(0.0, min(ax1, bx1) - max(ax0, bx0)) * max(
        0.0, min(ay1, by1) - max(ay0, by0)
    )
    area_a = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    area_b = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    return safe_div(intersection, area_a + area_b - intersection, 0.0)


def pair_metrics(
    cluster: dict[str, Any], vision: dict[str, Any], fov: dict[str, Any]
) -> dict[str, Any]:
    x_iou = interval_iou(
        float(cluster["x_min_mm"]),
        float(cluster["x_max_mm"]),
        float(vision["x_min_mm_est"]),
        float(vision["x_max_mm_est"]),
    )
    box_iou = bbox_iou(cluster, vision)
    cluster_length = float(cluster["length_x_mm"])
    vision_length = float(vision["length_x_mm_est"])
    relative_length_error = safe_div(
        abs(cluster_length - vision_length), max(cluster_length, vision_length), 0.0
    )
    cx_cluster = float(cluster.get("centroid_x_mm", 0.5 * (
        float(cluster["x_min_mm"]) + float(cluster["x_max_mm"])
    )))
    cy_cluster = float(cluster.get("centroid_y_mm", 0.5 * (
        float(cluster["y_min_mm"]) + float(cluster["y_max_mm"])
    )))
    cx_vision = float(vision.get("centroid_x_mm_est", 0.5 * (
        float(vision["x_min_mm_est"]) + float(vision["x_max_mm_est"])
    )))
    cy_vision = float(vision.get("centroid_y_mm_est", 0.5 * (
        float(vision["y_min_mm_est"]) + float(vision["y_max_mm_est"])
    )))
    x_error = abs(cx_cluster - cx_vision) / max(float(fov["width_mm"]), 1e-12)
    y_error = abs(cy_cluster - cy_vision) / max(float(fov["height_mm"]), 1e-12)
    geometry_eligible = x_iou >= 0.30 and x_error <= 0.20 and y_error <= 0.25
    position_match = x_iou >= 0.50 and x_error <= 0.10 and y_error <= 0.15
    score = (
        0.45 * x_iou
        + 0.25 * box_iou
        + 0.15 * max(0.0, 1.0 - relative_length_error)
        + 0.075 * max(0.0, 1.0 - x_error / 0.20)
        + 0.075 * max(0.0, 1.0 - y_error / 0.25)
    )
    return {
        "cluster_id": int(cluster["cluster_id"]),
        "vision_id": int(vision["vision_id"]),
        "sign_match": str(cluster["sign"]) == str(vision["sign"]),
        "streamwise_iou": x_iou,
        "bbox_iou": box_iou,
        "relative_length_error": relative_length_error,
        "centroid_x_error_fov": x_error,
        "centroid_y_error_fov": y_error,
        "position_match": position_match,
        "cluster_touches_fov_edge": bool(cluster.get("touches_fov_edge", False)),
        "vision_touches_fov_edge": bool(vision.get("touches_fov_edge", False)),
        "geometry_eligible": geometry_eligible,
        "assignment_score": score if geometry_eligible else 0.0,
    }


def maximum_weight_pairs(matrix: list[list[dict[str, Any]]]) -> list[tuple[int, int]]:
    n_cluster = len(matrix)
    n_vision = len(matrix[0]) if matrix else 0
    if not n_cluster or not n_vision:
        return []
    if n_vision > 14:
        candidates = sorted(
            (
                (cell["assignment_score"], i, j)
                for i, row in enumerate(matrix)
                for j, cell in enumerate(row)
                if cell["geometry_eligible"]
            ),
            reverse=True,
        )
        used_i: set[int] = set()
        used_j: set[int] = set()
        output = []
        for _, i, j in candidates:
            if i not in used_i and j not in used_j:
                output.append((i, j))
                used_i.add(i)
                used_j.add(j)
        return output

    @lru_cache(maxsize=None)
    def solve(i: int, used_mask: int) -> tuple[float, tuple[tuple[int, int], ...]]:
        if i >= n_cluster:
            return 0.0, ()
        best_score, best_pairs = solve(i + 1, used_mask)
        for j in range(n_vision):
            cell = matrix[i][j]
            if used_mask & (1 << j) or not cell["geometry_eligible"]:
                continue
            tail_score, tail_pairs = solve(i + 1, used_mask | (1 << j))
            candidate_score = float(cell["assignment_score"]) + tail_score
            if candidate_score > best_score + 1e-12:
                best_score = candidate_score
                best_pairs = ((i, j),) + tail_pairs
        return best_score, best_pairs

    return list(solve(0, 0)[1])


def score_frame(
    cluster_frame: dict[str, Any],
    vision_frame: dict[str, Any],
    fov: dict[str, Any],
) -> dict[str, Any]:
    cluster_objects = as_list(cluster_frame.get("cluster_objects", []))
    vision_objects = as_list(vision_frame.get("objects", []))
    matrix = [
        [pair_metrics(cluster, vision, fov) for vision in vision_objects]
        for cluster in cluster_objects
    ]
    assigned_indices = maximum_weight_pairs(matrix)
    matches = [matrix[i][j] for i, j in assigned_indices]
    signed_matches = [match for match in matches if match["sign_match"]]
    signed_cluster_indices = {
        i for (i, j), match in zip(assigned_indices, matches) if match["sign_match"]
    }
    signed_vision_indices = {
        j for (i, j), match in zip(assigned_indices, matches) if match["sign_match"]
    }
    unmatched_cluster_ids = [
        int(obj["cluster_id"])
        for i, obj in enumerate(cluster_objects)
        if i not in signed_cluster_indices
    ]
    unmatched_vision_ids = [
        int(obj["vision_id"])
        for j, obj in enumerate(vision_objects)
        if j not in signed_vision_indices
    ]
    tp = len(signed_matches)
    precision = safe_div(tp, len(cluster_objects), 1.0 if not vision_objects else 0.0)
    recall = safe_div(tp, len(vision_objects), 1.0 if not cluster_objects else 0.0)
    f1 = safe_div(2 * precision * recall, precision + recall, 1.0)
    edge_cluster = sum(bool(obj.get("touches_fov_edge", False)) for obj in cluster_objects)
    edge_vision = sum(bool(obj.get("touches_fov_edge", False)) for obj in vision_objects)
    edge_tp = sum(
        match["sign_match"]
        and match["cluster_touches_fov_edge"]
        and match["vision_touches_fov_edge"]
        for match in matches
    )
    return {
        "frame_id": int(cluster_frame["frame_id"]),
        "cluster_objects": cluster_objects,
        "vision_objects": vision_objects,
        "matches": matches,
        "unmatched_cluster_ids": unmatched_cluster_ids,
        "unmatched_vision_ids": unmatched_vision_ids,
        "cluster_false_positive_ids": unmatched_cluster_ids,
        "cluster_false_negative_vision_ids": unmatched_vision_ids,
        "counts": {
            "cluster": len(cluster_objects),
            "vision": len(vision_objects),
            "signed_true_positive": tp,
            "geometry_matches": len(matches),
            "sign_mismatches": len(matches) - tp,
            "edge_cluster": edge_cluster,
            "edge_vision": edge_vision,
            "edge_true_positive": edge_tp,
        },
        "metrics": {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "sign_accuracy": safe_div(tp, len(matches), 1.0),
            "streamwise_iou_median": median_or_none(
                match["streamwise_iou"] for match in signed_matches
            ),
            "bbox_iou_median": median_or_none(
                match["bbox_iou"] for match in signed_matches
            ),
            "length_relative_error_median": median_or_none(
                match["relative_length_error"] for match in signed_matches
            ),
            "position_match_rate": safe_div(
                sum(match["position_match"] for match in signed_matches), tp, 1.0
            ),
        },
    }


def score_round(
    round_id: int,
    cluster_data: dict[str, Any],
    visual_data: dict[str, Any],
    expected_n_frames: int,
) -> dict[str, Any]:
    cluster_frames = as_list(cluster_data.get("frames", []))
    visual_frames = as_list(visual_data.get("frames", []))
    cluster_by_id = {int(row["frame_id"]): row for row in cluster_frames}
    visual_by_id = {int(row["frame_id"]): row for row in visual_frames}
    frame_ids = [int(value) for value in cluster_data["frame_ids"]]
    missing_visual = [frame_id for frame_id in frame_ids if frame_id not in visual_by_id]
    scored_frames = [
        score_frame(cluster_by_id[frame_id], visual_by_id[frame_id], cluster_data["fov"])
        for frame_id in frame_ids
        if frame_id in cluster_by_id and frame_id in visual_by_id
    ]
    totals = {
        key: sum(frame["counts"][key] for frame in scored_frames)
        for key in [
            "cluster",
            "vision",
            "signed_true_positive",
            "geometry_matches",
            "sign_mismatches",
            "edge_cluster",
            "edge_vision",
            "edge_true_positive",
        ]
    }
    signed_matches = [
        match
        for frame in scored_frames
        for match in frame["matches"]
        if match["sign_match"]
    ]
    precision = safe_div(
        totals["signed_true_positive"],
        totals["cluster"],
        1.0 if not totals["vision"] else 0.0,
    )
    recall = safe_div(
        totals["signed_true_positive"],
        totals["vision"],
        1.0 if not totals["cluster"] else 0.0,
    )
    object_f1 = safe_div(2 * precision * recall, precision + recall, 1.0)
    edge_precision = safe_div(
        totals["edge_true_positive"],
        totals["edge_cluster"],
        1.0 if not totals["edge_vision"] else 0.0,
    )
    edge_recall = safe_div(
        totals["edge_true_positive"],
        totals["edge_vision"],
        1.0 if not totals["edge_cluster"] else 0.0,
    )
    edge_f1 = (
        None
        if not totals["edge_cluster"] and not totals["edge_vision"]
        else safe_div(2 * edge_precision * edge_recall, edge_precision + edge_recall, 0.0)
    )
    metrics = {
        "object_precision": precision,
        "object_recall": recall,
        "object_f1": object_f1,
        "sign_accuracy": safe_div(
            totals["signed_true_positive"], totals["geometry_matches"], 1.0
        ),
        "streamwise_iou_median": median_or_none(
            match["streamwise_iou"] for match in signed_matches
        ),
        "bbox_iou_median": median_or_none(match["bbox_iou"] for match in signed_matches),
        "length_relative_error_median": median_or_none(
            match["relative_length_error"] for match in signed_matches
        ),
        "length_relative_error_p90": percentile(
            (match["relative_length_error"] for match in signed_matches), 0.90
        ),
        "position_match_rate": safe_div(
            sum(match["position_match"] for match in signed_matches),
            len(signed_matches),
            1.0,
        ),
        "edge_object_precision": None if edge_f1 is None else edge_precision,
        "edge_object_recall": None if edge_f1 is None else edge_recall,
        "edge_object_f1": edge_f1,
    }
    checks = {
        "complete_36_frame_review": (
            visual_data.get("status") == "complete"
            and len(scored_frames) == expected_n_frames
            and not missing_visual
        ),
        "object_f1": metrics["object_f1"] >= THRESHOLDS["object_f1_min"],
        "sign_accuracy": metrics["sign_accuracy"] >= THRESHOLDS["sign_accuracy_min"],
        "streamwise_iou_median": (
            metrics["streamwise_iou_median"] is not None
            and metrics["streamwise_iou_median"]
            >= THRESHOLDS["streamwise_iou_median_min"]
        ),
        "length_relative_error_median": (
            metrics["length_relative_error_median"] is not None
            and metrics["length_relative_error_median"]
            <= THRESHOLDS["length_relative_error_median_max"]
        ),
        "position_match_rate": (
            metrics["position_match_rate"] >= THRESHOLDS["position_match_rate_min"]
        ),
        "edge_object_f1": (
            metrics["edge_object_f1"] is None
            or metrics["edge_object_f1"] >= THRESHOLDS["edge_object_f1_min"]
        ),
    }
    return {
        "round": round_id,
        "status": "pass" if all(checks.values()) else "fail",
        "missing_visual_frame_ids": missing_visual,
        "counts": totals,
        "metrics": metrics,
        "checks": checks,
        "frames": scored_frames,
    }


def fmt(value: Any, digits: int = 3) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, bool):
        return "PASS" if value else "FAIL"
    if isinstance(value, (float, int)):
        return f"{float(value):.{digits}f}"
    return str(value)


def object_description(obj: dict[str, Any], source: str) -> str:
    if source == "cluster":
        return (
            f"C{int(obj['cluster_id'])} {obj['sign']} "
            f"x=[{obj['x_min_mm']:.1f},{obj['x_max_mm']:.1f}] "
            f"y=[{obj['y_min_mm']:.1f},{obj['y_max_mm']:.1f}] "
            f"Lx={obj['length_x_mm']:.1f} mm "
            f"(Lx/delta={obj['length_over_delta']:.2f}, edge={obj['touches_fov_edge']})"
        )
    return (
        f"V{int(obj['vision_id'])} {obj['sign']} "
        f"x~[{obj['x_min_mm_est']:.1f},{obj['x_max_mm_est']:.1f}] "
        f"y~[{obj['y_min_mm_est']:.1f},{obj['y_max_mm_est']:.1f}] "
        f"Lx~{obj['length_x_mm_est']:.1f} mm "
        f"(edge={obj['touches_fov_edge']}, conf={obj['confidence']:.2f})"
    )


def write_round_markdown(attempt_dir: Path, round_result: dict[str, Any]) -> None:
    round_id = int(round_result["round"])
    lines = [
        f"# POD VLSM acceptance round {round_id:02d}",
        "",
        (
            "This is an operational comparison of 2C-2D XOY connected structures. "
            "GPT-5.6-SOL vision is an independent reference, not physical ground truth."
        ),
        "",
    ]
    for frame in round_result["frames"]:
        frame_id = int(frame["frame_id"])
        lines.extend(
            [
                f"## Frame {frame_id}",
                "",
                f"- Pure field: [image](pure_frames/frame_{frame_id:06d}.png)",
                f"- Cluster overlay: [image](cluster_frames/frame_{frame_id:06d}.png)",
                "- Cluster VLSM: "
                + ("; ".join(object_description(obj, "cluster") for obj in frame["cluster_objects"]) or "none"),
                "- GPT-5.6-SOL visual VLSM: "
                + ("; ".join(object_description(obj, "vision") for obj in frame["vision_objects"]) or "none"),
            ]
        )
        if frame["matches"]:
            match_text = "; ".join(
                (
                    f"C{match['cluster_id']}<->V{match['vision_id']} "
                    f"sign={match['sign_match']}, xIoU={match['streamwise_iou']:.2f}, "
                    f"bboxIoU={match['bbox_iou']:.2f}, "
                    f"lengthErr={match['relative_length_error']:.2f}, "
                    f"position={match['position_match']}"
                )
                for match in frame["matches"]
            )
        else:
            match_text = "none"
        lines.extend(
            [
                f"- Matches: {match_text}",
                f"- Unmatched cluster IDs: {frame['unmatched_cluster_ids']}",
                f"- Unmatched vision IDs: {frame['unmatched_vision_ids']}",
                "",
            ]
        )
    path = attempt_dir / f"round_{round_id:02d}" / f"round_{round_id:02d}_comparison.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def adjustment_recommendation(rounds: list[dict[str, Any]], parameters: dict[str, Any]) -> dict[str, Any]:
    failed = [row for row in rounds if row["status"] != "pass"]
    if not failed:
        return {
            "needed": False,
            "reason": "All three independent rounds passed every object-level threshold.",
            "proposed_parameters": parameters,
        }
    mean_precision = statistics.mean(row["metrics"]["object_precision"] for row in failed)
    mean_recall = statistics.mean(row["metrics"]["object_recall"] for row in failed)
    proposed = dict(parameters)
    if mean_recall + 0.05 < mean_precision:
        old = float(parameters["seed_alpha"])
        proposed["seed_alpha"] = max(float(parameters["alpha"]), round(old - 0.05, 3))
        reason = (
            "Cluster recall is the dominant failure mode; test a 0.05 lower seed_alpha "
            "while holding topology parameters fixed."
        )
    elif mean_precision + 0.05 < mean_recall:
        old = float(parameters["seed_alpha"])
        proposed["seed_alpha"] = round(old + 0.05, 3)
        reason = (
            "Cluster precision is the dominant failure mode; test a 0.05 higher seed_alpha "
            "while holding topology parameters fixed."
        )
    else:
        low_position = any(
            row["metrics"]["position_match_rate"] < THRESHOLDS["position_match_rate_min"]
            for row in failed
        )
        high_length_error = any(
            row["metrics"]["length_relative_error_median"] is None
            or row["metrics"]["length_relative_error_median"]
            > THRESHOLDS["length_relative_error_median_max"]
            for row in failed
        )
        if low_position or high_length_error:
            reason = (
                "Counts are not the dominant discrepancy. Inspect saved unmatched and length/"
                "position cases before changing connectivity or merge_gap_cells; no automatic "
                "topology change is justified."
            )
        else:
            reason = (
                "A threshold failed without a dominant precision/recall direction; retain the "
                "candidate until saved disagreement frames are inspected."
            )
    return {"needed": True, "reason": reason, "proposed_parameters": proposed}


def write_summary_markdown(
    attempt_dir: Path,
    manifest: dict[str, Any],
    rounds: list[dict[str, Any]],
    accepted: bool,
    recommendation: dict[str, Any],
) -> None:
    lines = [
        "# POD VLSM parameter acceptance (36 frames x 3 rounds)",
        "",
        f"Result: **{'PASS' if accepted else 'FAIL - parameter adjustment required'}**",
        "",
        (
            "Agreement is object-level: sign, streamwise and wall-normal position, visible "
            "length, and FOV-edge status. Count agreement alone is not used for acceptance."
        ),
        "",
        "## Candidate parameters",
        "",
        "```json",
        json.dumps(manifest["parameters"], ensure_ascii=False, indent=2),
        "```",
        "",
        "## Acceptance thresholds",
        "",
        "```json",
        json.dumps(THRESHOLDS, indent=2),
        "```",
        "",
        "## Round metrics",
        "",
        "| Round | F1 | Sign | x IoU median | Length error median | Position | Edge F1 | Result |",
        "|---:|---:|---:|---:|---:|---:|---:|:---|",
    ]
    for row in rounds:
        metric = row["metrics"]
        lines.append(
            f"| {row['round']} | {fmt(metric['object_f1'])} | "
            f"{fmt(metric['sign_accuracy'])} | {fmt(metric['streamwise_iou_median'])} | "
            f"{fmt(metric['length_relative_error_median'])} | "
            f"{fmt(metric['position_match_rate'])} | {fmt(metric['edge_object_f1'])} | "
            f"{row['status'].upper()} |"
        )
    lines.extend(
        [
            "",
            "## Decision",
            "",
            recommendation["reason"],
            "",
            (
                "Scope: connected structures in the 2C-2D XOY POD reconstruction. GPT vision "
                "is an operational independent reference, not physical or three-dimensional truth."
            ),
            "",
        ]
    )
    (attempt_dir / "acceptance_report.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def main() -> int:
    args = parse_args()
    attempt_dir = args.attempt_dir.resolve()
    manifest = read_json(attempt_dir / "manifest.json")
    rounds = []
    for round_id in range(1, int(manifest["n_rounds"]) + 1):
        round_dir = attempt_dir / f"round_{round_id:02d}"
        cluster_data = read_json(round_dir / f"round_{round_id:02d}_cluster_objects.json")
        visual_data = read_json(round_dir / f"round_{round_id:02d}_visual_review.json")
        result = score_round(
            round_id,
            cluster_data,
            visual_data,
            int(manifest["n_frames_per_round"]),
        )
        rounds.append(result)
        write_json(round_dir / f"round_{round_id:02d}_matches.json", result)
        write_round_markdown(attempt_dir, result)

    accepted = len(rounds) == 3 and all(row["status"] == "pass" for row in rounds)
    recommendation = adjustment_recommendation(rounds, manifest["parameters"])
    summary = {
        "schema_version": 1,
        "status": "accepted" if accepted else "adjustment_required",
        "three_round_acceptance_passed": accepted,
        "thresholds": THRESHOLDS,
        "parameters": manifest["parameters"],
        "rounds": [
            {
                "round": row["round"],
                "status": row["status"],
                "counts": row["counts"],
                "metrics": row["metrics"],
                "checks": row["checks"],
            }
            for row in rounds
        ],
        "parameter_adjustment": recommendation,
        "interpretation_limit": manifest["interpretation_limit"],
    }
    write_json(attempt_dir / "acceptance_summary.json", summary)
    write_json(attempt_dir / "parameter_adjustment_recommendation.json", recommendation)
    write_summary_markdown(attempt_dir, manifest, rounds, accepted, recommendation)
    print(f"Acceptance status: {summary['status']}")
    for row in rounds:
        print(
            f"  round {row['round']:02d}: {row['status']} "
            f"F1={row['metrics']['object_f1']:.3f} "
            f"sign={row['metrics']['sign_accuracy']:.3f}"
        )
    return 0 if accepted else 3


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"acceptance scoring failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
