#!/usr/bin/env python3
"""
Fable 5 视觉审核脚本 - 替代 gpt-5.6-sol
对 POD 重构流向脉动场图像进行 VLSM 结构识别

使用 Agent 工具调用 Fable 5 子代理进行视觉识别
"""

import json
import sys
from pathlib import Path
from typing import List, Dict, Any
import argparse


def load_visual_context(round_dir: Path) -> Dict[str, Any]:
    """加载轮次的视觉上下文信息"""
    context_file = round_dir / f"{round_dir.name}_visual_context.json"
    with open(context_file, 'r', encoding='utf-8') as f:
        return json.load(f)


def build_fable5_prompt(frame_paths: List[Path], context: Dict[str, Any]) -> str:
    """构建 Fable 5 子代理的视觉识别 prompt"""

    # 提取 FOV 和色标信息
    fov = context['fov']
    colorbar_limit = context.get('colorbar_abs_limit_m_per_s', 3.0)
    delta99 = context['delta99_mm']

    prompt = f"""你是湍流结构识别专家。请对以下 POD 重构流向脉动场图像进行 VLSM（Very Large Scale Motion）结构识别。

**场信息：**
- 场类型：POD 50% 能量重构的流向脉动 u'(x,y)
- 色标范围：±{colorbar_limit} m/s（红色=正脉动，蓝色=负脉动）
- FOV 范围：x ∈ [{fov['x_min_mm']:.1f}, {fov['x_max_mm']:.1f}] mm，y ∈ [{fov['y_min_mm']:.1f}, {fov['y_max_mm']:.1f}] mm
- 边界层特征尺度：δ99 = {delta99:.2f} mm

**VLSM 定义：**
- 流向长度 Lx ≥ 3×δ99（即 ≥{3*delta99:.1f} mm）
- 连续的同号（全正或全负）脉动区域
- 可触及 FOV 边缘（保留可见部分）

**识别要求：**
1. 仅识别明显的、连续的同号条带状结构
2. 估计每个结构的：
   - 符号（positive/negative）
   - 流向范围 [x_min, x_max] mm
   - 法向范围 [y_min, y_max] mm
   - 流向长度 Lx = x_max - x_min
   - 是否触及 FOV 边缘（touches_fov_edge: true/false）
   - 置信度（0-1）
   - 简短说明（中文，描述位置和形态）

3. 如果某帧无明显 VLSM，返回空列表

**输出格式（JSON）：**
对每张图像返回：
```json
{{
  "frame_id": <帧号>,
  "vlsm_objects": [
    {{
      "sign": "positive" or "negative",
      "x_min_mm": <数值>,
      "x_max_mm": <数值>,
      "y_min_mm": <数值>,
      "y_max_mm": <数值>,
      "length_x_mm": <数值>,
      "touches_fov_edge": <bool>,
      "confidence": <0-1>,
      "notes": "<中文说明>"
    }}
  ]
}}
```

现在请依次识别以下 {len(frame_paths)} 张图像。
"""

    return prompt


def parse_fable5_response(response_text: str, frame_ids: List[int]) -> List[Dict[str, Any]]:
    """解析 Fable 5 的响应文本，提取 JSON 结果"""
    results = []

    # 尝试提取 JSON 代码块
    import re
    json_blocks = re.findall(r'```json\s*(.*?)\s*```', response_text, re.DOTALL)

    if not json_blocks:
        # 尝试直接解析整个响应
        try:
            data = json.loads(response_text)
            if isinstance(data, list):
                results = data
            elif isinstance(data, dict):
                results = [data]
        except json.JSONDecodeError:
            print(f"警告：无法解析 Fable 5 响应为 JSON", file=sys.stderr)
            # 返回空结果
            for frame_id in frame_ids:
                results.append({
                    'frame_id': frame_id,
                    'vlsm_objects': [],
                    'parse_error': True
                })
            return results

    # 解析提取的 JSON 块
    for block in json_blocks:
        try:
            data = json.loads(block)
            if isinstance(data, list):
                results.extend(data)
            else:
                results.append(data)
        except json.JSONDecodeError as e:
            print(f"警告：JSON 块解析失败: {e}", file=sys.stderr)
            continue

    # 确保所有帧都有结果
    found_frame_ids = {r['frame_id'] for r in results if 'frame_id' in r}
    for frame_id in frame_ids:
        if frame_id not in found_frame_ids:
            results.append({
                'frame_id': frame_id,
                'vlsm_objects': []
            })

    return results


def review_round_with_fable5(attempt_dir: Path, round_num: int, batch_size: int = 6) -> Dict[str, Any]:
    """使用 Fable 5 对一轮进行视觉审核"""

    round_dir = attempt_dir / f"round_{round_num:02d}"
    pure_frames_dir = round_dir / "pure_frames"

    # 加载上下文
    context = load_visual_context(round_dir)
    frame_ids = context['frame_ids']

    print(f"Round {round_num:02d}: 开始 Fable 5 视觉审核，共 {len(frame_ids)} 帧")

    # 收集所有纯场图路径
    frame_paths = []
    for frame_id in frame_ids:
        frame_path = pure_frames_dir / f"frame_{frame_id:06d}.png"
        if not frame_path.exists():
            print(f"错误：帧图像不存在 {frame_path}", file=sys.stderr)
            sys.exit(1)
        frame_paths.append(frame_path)

    # 分批处理
    all_results = []
    num_batches = (len(frame_paths) + batch_size - 1) // batch_size

    for batch_idx in range(num_batches):
        start_idx = batch_idx * batch_size
        end_idx = min(start_idx + batch_size, len(frame_paths))
        batch_paths = frame_paths[start_idx:end_idx]
        batch_frame_ids = frame_ids[start_idx:end_idx]

        print(f"  批次 {batch_idx+1}/{num_batches}: 帧 {batch_frame_ids[0]}-{batch_frame_ids[-1]}")

        # 构建 prompt
        prompt = build_fable5_prompt(batch_paths, context)

        # 这里需要调用 Agent 工具创建 Fable 5 子代理
        # 由于工具调用限制，这里先生成调用指令，由主会话执行
        agent_call = {
            'model': 'fable',
            'prompt': prompt,
            'image_paths': [str(p) for p in batch_paths],
            'batch_frame_ids': batch_frame_ids
        }

        # 暂存调用指令
        batch_call_file = round_dir / f"fable5_batch_{batch_idx+1:02d}_call.json"
        with open(batch_call_file, 'w', encoding='utf-8') as f:
            json.dump(agent_call, f, indent=2, ensure_ascii=False)

        print(f"    已生成 Fable 5 调用指令: {batch_call_file}")
        print(f"    请手动执行：Agent(model='fable', prompt=<见文件>, images=<见文件>)")

        # TODO: 实际环境中需要通过某种方式调用 Agent 并获取响应
        # 这里先假设响应已经保存在对应的文件中
        batch_response_file = round_dir / f"fable5_batch_{batch_idx+1:02d}_response.json"

        if batch_response_file.exists():
            with open(batch_response_file, 'r', encoding='utf-8') as f:
                response_data = json.load(f)
                batch_results = response_data.get('results', [])
                all_results.extend(batch_results)
        else:
            print(f"    警告：等待响应文件 {batch_response_file}")
            # 生成占位结果
            for frame_id in batch_frame_ids:
                all_results.append({
                    'frame_id': frame_id,
                    'vlsm_objects': [],
                    'status': 'pending_fable5_response'
                })

    # 构建最终输出
    output = {
        'round': round_num,
        'model': 'fable-5',
        'total_frames': len(frame_ids),
        'frames_reviewed': len([r for r in all_results if r.get('status') != 'pending_fable5_response']),
        'frames': all_results
    }

    # 保存结果
    output_file = round_dir / f"round_{round_num:02d}_visual_review.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"Round {round_num:02d}: 视觉审核结果已保存至 {output_file}")

    return output


def main():
    parser = argparse.ArgumentParser(description='Fable 5 POD-VLSM 视觉审核')
    parser.add_argument('--attempt-dir', required=True, help='Attempt 目录路径')
    parser.add_argument('--round', type=int, required=True, help='轮次编号 (1-3)')
    parser.add_argument('--batch-size', type=int, default=6, help='批处理大小')

    args = parser.parse_args()

    attempt_dir = Path(args.attempt_dir)
    if not attempt_dir.exists():
        print(f"错误：目录不存在 {attempt_dir}", file=sys.stderr)
        sys.exit(1)

    result = review_round_with_fable5(attempt_dir, args.round, args.batch_size)

    if result['frames_reviewed'] == result['total_frames']:
        print(f"\n✓ Round {args.round:02d} 审核完成")
    else:
        print(f"\n⚠ Round {args.round:02d} 审核未完成，请执行生成的 Fable 5 调用指令")
        print(f"   已审核: {result['frames_reviewed']}/{result['total_frames']}")


if __name__ == '__main__':
    main()
