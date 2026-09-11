# -*- coding: utf-8 -*-
"""基于人工标注 Ground Truth 评价聚类参数配置的性能。

评价指标：
- IoU (Intersection over Union): 聚类框与标注框的重叠度
- Precision: 聚类结果中有多少是真阳性
- Recall: 标注结果中有多少被正确检出
- F1-score: Precision 和 Recall 的调和平均

用法:
    python tools/research/r2_diagnostics/evaluate_clustering_vs_annotation.py \\
        --annotation tmp/annotation_samples/e60/annotation_completed.json \\
        --clustering tmp/pod_energy_series_opt/attempt_34/manifest.json \\
        --output tmp/evaluation_results/e60_attempt34.json
"""
import argparse
import json
import sys
from pathlib import Path
import numpy as np

def load_annotation(annotation_file):
    """加载人工标注的 Ground Truth."""
    with open(annotation_file, encoding='utf-8') as fp:
        data = json.load(fp)

    gt = {}
    for key, frame_data in data['frames'].items():
        if frame_data['annotation_status'] != 'completed':
            continue
        fid = int(frame_data['frame_id'])
        boxes = []
        for box in frame_data.get('vlsm_boxes', []):
            boxes.append({
                'x_min': float(box['x_min']),
                'x_max': float(box['x_max']),
                'y_min': float(box['y_min']),
                'y_max': float(box['y_max']),
            })
        gt[fid] = boxes
    return gt


def load_clustering_result(manifest_file):
    """加载聚类算法识别结果."""
    with open(manifest_file, encoding='utf-8') as fp:
        manifest = json.load(fp)

    pred = {}
    for round_data in manifest['rounds']:
        for fid_str, structures in round_data['structures'].items():
            fid = int(fid_str)
            if fid not in pred:
                pred[fid] = []
            for s in structures:
                pred[fid].append({
                    'x_min': float(s['XMin_mm']),
                    'x_max': float(s['XMax_mm']),
                    'y_min': float(s['YMin_mm']),
                    'y_max': float(s['YMax_mm']),
                })
    return pred


def compute_iou(box1, box2):
    """计算两个边界框的 IoU."""
    x_overlap = max(0, min(box1['x_max'], box2['x_max']) - max(box1['x_min'], box2['x_min']))
    y_overlap = max(0, min(box1['y_max'], box2['y_max']) - max(box1['y_min'], box2['y_min']))
    intersection = x_overlap * y_overlap

    area1 = (box1['x_max'] - box1['x_min']) * (box1['y_max'] - box1['y_min'])
    area2 = (box2['x_max'] - box2['x_min']) * (box2['y_max'] - box2['y_min'])
    union = area1 + area2 - intersection

    return intersection / union if union > 0 else 0.0


def match_boxes(gt_boxes, pred_boxes, iou_threshold=0.5):
    """匹配 Ground Truth 和预测框，返回 TP/FP/FN."""
    gt_matched = [False] * len(gt_boxes)
    pred_matched = [False] * len(pred_boxes)

    matches = []
    for i, gt_box in enumerate(gt_boxes):
        best_iou = 0
        best_j = -1
        for j, pred_box in enumerate(pred_boxes):
            if pred_matched[j]:
                continue
            iou = compute_iou(gt_box, pred_box)
            if iou > best_iou:
                best_iou = iou
                best_j = j

        if best_iou >= iou_threshold:
            gt_matched[i] = True
            pred_matched[best_j] = True
            matches.append({'gt_idx': i, 'pred_idx': best_j, 'iou': best_iou})

    tp = sum(gt_matched)
    fp = len(pred_boxes) - sum(pred_matched)
    fn = len(gt_boxes) - sum(gt_matched)

    return tp, fp, fn, matches


def evaluate(gt, pred, iou_threshold=0.5):
    """评价整个数据集."""
    total_tp = 0
    total_fp = 0
    total_fn = 0
    frame_results = {}

    all_frames = set(gt.keys()) | set(pred.keys())

    for fid in sorted(all_frames):
        gt_boxes = gt.get(fid, [])
        pred_boxes = pred.get(fid, [])

        tp, fp, fn, matches = match_boxes(gt_boxes, pred_boxes, iou_threshold)
        total_tp += tp
        total_fp += fp
        total_fn += fn

        frame_results[fid] = {
            'gt_count': len(gt_boxes),
            'pred_count': len(pred_boxes),
            'tp': tp,
            'fp': fp,
            'fn': fn,
            'matches': matches,
        }

    precision = total_tp / (total_tp + total_fp) if (total_tp + total_fp) > 0 else 0.0
    recall = total_tp / (total_tp + total_fn) if (total_tp + total_fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

    return {
        'total_tp': total_tp,
        'total_fp': total_fp,
        'total_fn': total_fn,
        'precision': precision,
        'recall': recall,
        'f1_score': f1,
        'iou_threshold': iou_threshold,
        'frame_results': frame_results,
    }


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--annotation', required=True, help='人工标注 JSON 文件')
    ap.add_argument('--clustering', required=True, help='聚类结果 manifest.json')
    ap.add_argument('--output', required=True, help='输出评价结果 JSON')
    ap.add_argument('--iou-threshold', type=float, default=0.5, help='IoU 匹配阈值')
    args = ap.parse_args(argv)

    print(f'[加载] 标注: {args.annotation}')
    gt = load_annotation(args.annotation)
    print(f'  标注帧数: {len(gt)}, 总 VLSM 数: {sum(len(boxes) for boxes in gt.values())}')

    print(f'[加载] 聚类: {args.clustering}')
    pred = load_clustering_result(args.clustering)
    print(f'  聚类帧数: {len(pred)}, 总 VLSM 数: {sum(len(boxes) for boxes in pred.values())}')

    print(f'[评价] IoU 阈值: {args.iou_threshold}')
    results = evaluate(gt, pred, args.iou_threshold)

    print(f'\n=== 评价结果 ===')
    print(f'TP: {results["total_tp"]}')
    print(f'FP: {results["total_fp"]}')
    print(f'FN: {results["total_fn"]}')
    print(f'Precision: {results["precision"]:.3f}')
    print(f'Recall: {results["recall"]:.3f}')
    print(f'F1-score: {results["f1_score"]:.3f}')

    with open(args.output, 'w', encoding='utf-8') as fp:
        json.dump(results, fp, indent=2)
    print(f'\n[写入] {args.output}')

    return 0


if __name__ == '__main__':
    sys.exit(main())
