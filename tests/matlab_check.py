#!/usr/bin/env python3
"""matlab_check.py — MATLAB 源文件静态结构检查（轻量、非编译器）。

移植自 tbl_piv_turbulence/tests/matlab_check.py，适配本仓库扫描范围：
默认递归检查 lib/、tests/、cases/、tools/，跳过 third_party/、other_case_scripts/、
archive/、.reasonix/ 与输出目录 output/。

逐文件检查：
  1. 括号 ()[]{} 平衡（跳过字符串与注释）
  2. 单引号/双引号字符串配对（'' 转义）
  3. 块关键字 if/for/while/switch/function/try 与 end 计数配对（粗略）
  4. 常见非法语法模式：`?` 三元、`elif`
  5. 主函数名与文件名一致

用法：python3 tests/matlab_check.py [file_or_dir...]
退出码：0 = 无错误；1 = 有错误。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_TARGETS = [os.path.join(ROOT, "lib"),
                   os.path.join(ROOT, "tests"),
                   os.path.join(ROOT, "cases"),
                   os.path.join(ROOT, "tools")]
SKIP_DIRS = {"third_party", "other_case_scripts", "archive", ".reasonix",
             "output", "results", "pyenv", ".git"}

ERR = []


def strip_comments(line):
    """去除 % 注释（% 在字符串内时保留）。"""
    out = []
    i = 0
    in_str = None  # None | "'" | '"'
    while i < len(line):
        c = line[i]
        if in_str:
            out.append(c)
            if c == in_str:
                if i + 1 < len(line) and line[i + 1] == in_str:  # 转义 ''/ ""
                    out.append(line[i + 1])
                    i += 2
                    continue
                in_str = None
            i += 1
            continue
        if c in "'\"":
            in_str = c
            out.append(c)
            i += 1
            continue
        if c == "%":
            break  # 注释到行尾
        out.append(c)
        i += 1
    return "".join(out), in_str


def is_transpose(code, i):
    """转置 ' 总是紧跟在表达式后：字母/数字/_/)/]/}/.' 之后。"""
    if i == 0:
        return False
    prev = code[i - 1]
    return prev.isalnum() or prev in ")]}." or prev == "_"


def strip_literals(line):
    """去除 % 注释与字符串内容（长度保留、引号保留），供括号/关键字检查。

    MATLAB 字符串内的括号、end、if 等不应参与配对统计；字符串内容替换
    为空格但保留引号字符，使后续转置 ' 检测不受影响。
    """
    out = []
    i = 0
    in_str = None
    while i < len(line):
        c = line[i]
        if in_str:
            if c == in_str:
                if i + 1 < len(line) and line[i + 1] == in_str:  # 转义 ''/ ""
                    out.append("  ")
                    i += 2
                    continue
                out.append(c)  # 保留闭合引号
                in_str = None
            else:
                out.append(" ")  # 字符串内容替换为空格
            i += 1
            continue
        if c in "'\"":
            if c == "'" and is_transpose(line, i):
                out.append(c)  # 转置运算符
            else:
                in_str = c
                out.append(c)
            i += 1
            continue
        if c == "%":
            break
        out.append(c)
        i += 1
    return "".join(out)


def check_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    name = os.path.basename(path)
    code_lines = []
    for ln, raw in enumerate(lines, 1):
        code, _ = strip_comments(raw)
        code_lines.append((ln, code))
    literal_lines = [(ln, strip_literals(raw)) for ln, raw in enumerate(lines, 1)]

    # ---- 1. 括号平衡（字符串/注释内容已剥离） ----
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for ln, code in literal_lines:
        for c in code:
            if c in "([{":
                stack.append((c, ln))
            elif c in ")]}":
                if not stack or stack[-1][0] != pairs[c]:
                    ERR.append(f"{name}:{ln}: 括号不匹配 '{c}'")
                    return
                stack.pop()
    for c, ln in stack:
        ERR.append(f"{name}:{ln}: 未闭合括号 '{c}'")

    # ---- 2. 字符串配对（区分转置运算符 ' 与字符串引号） ----
    for ln, code in code_lines:
        in_str = None
        i = 0
        while i < len(code):
            c = code[i]
            if in_str:
                if c == in_str:
                    if i + 1 < len(code) and code[i + 1] == in_str:
                        i += 2
                        continue
                    in_str = None
            elif c in "'\"":
                if c == "'" and is_transpose(code, i):
                    pass  # 转置运算符
                else:
                    in_str = c
            i += 1
        if in_str:
            ERR.append(f"{name}:{ln}: 未闭合字符串")

    # ---- 3. 块关键字配对（粗略计数，字符串/注释已剥离） ----
    def count(ln, code, pat):
        return len(re.findall(pat, code))

    opens = closes = 0
    for ln, code in literal_lines:
        opens += count(ln, code, r"\b(if|for|while|switch|function|try|parfor)\b")
        closes += count(ln, code, r"\bend\b")
        # end 作为矩阵/向量/cell 索引（x(end)、x(end-1)、lbl(end+1)、x(end,:)、
        # c{end}）不计。字符集必须含 '}'，否则 c{end} 会被误判成块结束符。
        closes -= count(ln, code, r"\bend\s*[)\]},\-+:]")
    if opens != closes:
        ERR.append(f"{name}: 块关键字 if/for/while/switch/function/try 共 {opens} 个，"
                   f"end 共 {closes} 个（粗略检查，可能误报）")

    # ---- 4. 常见非法模式（字符串/注释已剥离） ----
    for ln, code in literal_lines:
        if "?" in code:
            ERR.append(f"{name}:{ln}: 出现 '?'（MATLAB 无三元运算符）")
        if re.search(r"\belif\b", code):
            ERR.append(f"{name}:{ln}: 'elif' 非法（MATLAB 用 elseif）")

    # ---- 5. 主函数名与文件名一致 ----
    first = code_lines[0][1] if code_lines else ""
    m = re.search(r"^\s*function\s+(?:\[[^\]]*\]\s*=\s*)?([A-Za-z_]\w*)\s*\(", first)
    if m and not name.lower().startswith(m.group(1).lower()):
        ERR.append(f"{name}: 主函数名 '{m.group(1)}' 与文件名 '{name}' 不一致")


def main(argv):
    targets = argv[1:] or DEFAULT_TARGETS
    files = []
    for t in targets:
        if not os.path.exists(t):
            ERR.append(f"目标不存在: {t}")
            continue
        if os.path.isdir(t):
            for root, dirs, fs in os.walk(t):
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
                for f in fs:
                    if f.endswith(".m"):
                        files.append(os.path.join(root, f))
        elif t.endswith(".m"):
            files.append(t)
    files.sort()
    if not files:
        print("未找到 .m 文件")
        return 1
    for f in files:
        check_file(f)
    if ERR:
        for e in ERR:
            print(f"  [ERR] {e}")
        print(f"\n{len(ERR)} 个问题")
        return 1
    print(f"检查通过：{len(files)} 个 .m 文件无结构错误")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
