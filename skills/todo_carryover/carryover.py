#!/usr/bin/env python3
"""
SideNote Task Carryover Skill
=================================
昨日未完成任务 + 今日已有任务 → LLM 合并整理 → 写入今日 AI Inbox

使用方式:
  python3 carryover.py                        # 处理所有分类
  python3 carryover.py --category work        # 只处理指定分类
  python3 carryover.py --dry-run              # 只预览，不写入
  python3 carryover.py --date 2026-04-14      # 指定昨日日期（用于测试）
  python3 carryover.py --today-only           # 只整理今日任务，不处理昨日

环境变量:
  SIDENOTE_LLM_API_KEY    LLM API Key（不设置则降级为直接合并）
  SIDENOTE_LLM_MODEL      模型名（默认 gpt-4o-mini）
  SIDENOTE_LLM_ENDPOINT   自定义 API 端点（可选）

依赖:
  pip install openai

作者: Hermes Agent
"""

import os
import sys
import json
import argparse
import datetime
from pathlib import Path
from typing import List, Optional

# ============================================================
# 配置
# ============================================================

ARCHIVE_DIR = Path.home() / "Documents" / "SideNote_Archive" / "Current_Week"
DAILY_DIR = ARCHIVE_DIR / "Daily"
CATEGORIES = ["work", "dev", "life"]
CATEGORY_LABELS = {"work": "工作", "dev": "个人开发", "life": "生活"}
INBOX_HEADER = "--- 昨日遗留 + 今日任务（合并整理）---"


# ============================================================
# 第一步: 读取任务（昨日未完成 + 今日已有）
# ============================================================

def load_yesterday_unfinished(
    date_str: str,
    category: str,
) -> List[str]:
    """
    读取昨日切片文件，提取未完成的任务（☐ 开头的行）。

    参数:
        date_str:  日期字符串，格式 "yyyy-MM-dd"
        category:  分类名，如 "work"、"dev"、"life"

    返回:
        未完成任务的文本列表（已去除 ☐ 前缀）
    """
    daily_file = DAILY_DIR / f"{date_str}_{category}.txt"

    if not daily_file.exists():
        print(f"  ⚠  昨日文件不存在: {daily_file.name}")
        return []

    tasks = []
    with open(daily_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    for line in lines:
        line = line.strip()
        if line.startswith("☐"):
            task = line.replace("☐", "", 1).strip()
            if task and not task.startswith("---"):
                tasks.append(task)

    return tasks


def load_today_tasks(
    today_str: str,
    category: str,
) -> List[str]:
    """
    读取今日切片文件，提取所有任务（☐ 未完成 + ☑ 已完成）。

    今日完成的任务也读取出来，这样 LLM 可以看到完整的上下文，
    知道哪些已经在今天做了，避免重复安排。

    参数:
        today_str:  今日日期字符串，格式 "yyyy-MM-dd"
        category:   分类名

    返回:
        今日所有任务的文本列表（标记 [已完成] 或 [未完成]）
    """
    daily_file = DAILY_DIR / f"{today_str}_{category}.txt"

    if not daily_file.exists():
        print(f"  ⚠  今日文件不存在: {daily_file.name}")
        return []

    tasks = []
    with open(daily_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    for line in lines:
        line = line.strip()
        if line.startswith("☑"):
            task = line.replace("☑", "", 1).strip()
            if task and not task.startswith("---"):
                tasks.append(f"[已完成] {task}")
        elif line.startswith("☐"):
            task = line.replace("☐", "", 1).strip()
            if task and not task.startswith("---"):
                tasks.append(f"[未完成] {task}")

    return tasks


# ============================================================
# 第二步: LLM 合并整理
# ============================================================

def build_prompt(
    category: str,
    yesterday_tasks: List[str],
    today_tasks: List[str],
    yesterday_str: str,
    today_str: str,
    weekday_cn: str,
) -> tuple:
    """
    构建 LLM 调用所需的 system 和 user prompt。

    返回:
        (system_prompt, user_prompt)
    """
    system_prompt = """你是一个待办事项整理助手。你会收到两类任务：

A. 昨天未完成的任务（需要延续到今天）
B. 今天已有的任务（部分已完成、部分未完成）

请严格按以下步骤处理：

1. **去重合并** — 将 A 和 B 中表述不同但语义相同的任务合并为一条
2. **语义归类** — 将松散任务按语义分组，每组用【分组名】单独一行做标题
3. **优先级排序** — 紧急且重要 > 重要不紧急 > 紧急不重要 > 其他
4. **清晰化重写** — 模糊任务改写为具体可执行的形式

特别注意：
- 对于今天【已完成】的任务，如果已在昨天遗留中找到，说明用户已经做了，不要再次列入
- 整理后的列表应该是「今天还需要做的事情」，而不是已完成事项的回顾
- 合理判断任务的实际优先级，不要机械保留所有任务

输出规则（严格遵守）：
- 只输出任务文本本身，每行一条
- 分组标题用【】包裹，独占一行
- 不要编号，不要项目符号（- 或 *）
- 不要添加 ☐ 符号（系统会自动添加）
- 不要添加任何 AI 说明、问候语、总结
- 不要在末尾添加额外空行

按优先级从高到低排列。"""

    # 构建输入文本
    parts = []
    if yesterday_tasks:
        parts.append(f"【昨天未完成】\n" + "\n".join(f"- {t}" for t in yesterday_tasks))
    if today_tasks:
        parts.append(f"\n【今天已有】\n" + "\n".join(f"- {t}" for t in today_tasks))

    task_text = "\n".join(parts)

    context_parts = []
    if yesterday_tasks:
        context_parts.append(f"昨天（{yesterday_str}）遗留下来的未完成任务")
    if today_tasks:
        context_parts.append(f"今天（{today_str}）已有的任务")
    source_desc = "和".join(context_parts) if context_parts else "任务"

    user_prompt = f"""今天是星期{weekday_cn}（{today_str}），以下是来自{source_desc}的「{CATEGORY_LABELS.get(category, category)}」分类中的任务：

{task_text}

请将这些任务合并整理，去重、归类、按优先级排序，只输出今天还需要做的事情。"""

    return system_prompt, user_prompt


def call_llm(
    system_prompt: str,
    user_prompt: str,
) -> Optional[str]:
    """
    调用 LLM API 进行任务整理。

    支持 OpenAI 兼容接口。可通过环境变量配置：
    - SIDENOTE_LLM_API_KEY:   API Key（必需，否则返回 None）
    - SIDENOTE_LLM_MODEL:     模型名（默认 gpt-4o-mini）
    - SIDENOTE_LLM_ENDPOINT:  自定义端点（可选）

    返回:
        LLM 返回的文本，或 None（调用失败时）
    """
    api_key = os.environ.get("SIDENOTE_LLM_API_KEY")
    if not api_key:
        print("  ⚠  未设置 SIDENOTE_LLM_API_KEY，跳过 LLM 整理")
        return None

    model = os.environ.get("SIDENOTE_LLM_MODEL", "gpt-4o-mini")
    endpoint = os.environ.get("SIDENOTE_LLM_ENDPOINT")

    try:
        from openai import OpenAI

        client_kwargs = {"api_key": api_key}
        if endpoint:
            client_kwargs["base_url"] = endpoint

        client = OpenAI(**client_kwargs)

        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.3,
            max_tokens=1024,
        )

        return response.choices[0].message.content

    except ImportError:
        print("  ⚠  未安装 openai 库，请运行: pip install openai")
        return None
    except Exception as e:
        print(f"  ⚠  LLM 调用失败: {e}")
        return None


def parse_llm_output(text: str) -> List[str]:
    """
    解析 LLM 输出，提取任务行。

    过滤规则：
    - 去除空行
    - 去除可能的 AI 自述行（"好的"、"根据"、"以下" 开头）
    - 保留分组标题行（【】包裹）
    - 保留任务行
    """
    lines = []
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        if any(line.startswith(prefix) for prefix in ["好的", "根据", "以下", "---", "当然"]):
            continue
        lines.append(line)
    return lines


def organize_tasks(
    category: str,
    yesterday_tasks: List[str],
    today_tasks: List[str],
    yesterday_str: str,
    today_str: str,
    weekday_cn: str,
) -> List[str]:
    """
    主整理函数：调用 LLM 合并整理任务，LLM 不可用时降级为简单合并。

    参数:
        category:        分类名
        yesterday_tasks: 昨日未完成任务列表
        today_tasks:     今日已有任务列表
        yesterday_str:   昨日日期字符串
        today_str:       今日日期字符串
        weekday_cn:      中文星期几

    返回:
        整理后的任务列表
    """
    system_prompt, user_prompt = build_prompt(
        category, yesterday_tasks, today_tasks,
        yesterday_str, today_str, weekday_cn,
    )

    result = call_llm(system_prompt, user_prompt)

    if result is None:
        # 降级策略：LLM 不可用时，合并去重后返回
        print(f"  → 使用降级策略：简单合并去重")
        return merge_fallback(yesterday_tasks, today_tasks)

    organized = parse_llm_output(result)
    total_in = len(yesterday_tasks) + len(today_tasks)
    print(f"  → LLM 整理完成: {total_in} 项 → {organized} 项")
    return organized


def merge_fallback(
    yesterday_tasks: List[str],
    today_tasks: List[str],
) -> List[str]:
    """
    降级合并策略：简单去重后合并，保持顺序。

    从 today_tasks 中提取未完成的纯任务文本（去掉 [已完成]/[未完成] 标记），
    与 yesterday_tasks 合并去重。
    """
    # 提取今日未完成的任务（去掉标记）
    today_unfinished = []
    for t in today_tasks:
        cleaned = t.replace("[已完成] ", "").replace("[未完成] ", "")
        if t.startswith("[已完成]"):
            # 已完成的跳过（LLM 不在时简单处理）
            continue
        today_unfinished.append(cleaned)

    # 简单去重合并：yesterday + today（保持 yesterday 优先）
    seen = set()
    merged = []
    for task in yesterday_tasks + today_unfinished:
        # 简单去重：用前 10 个字作为 key
        key = task[:10]
        if key not in seen:
            seen.add(key)
            merged.append(task)

    return merged


# ============================================================
# 第三步: 写入 AI Inbox
# ============================================================

def write_to_inbox(
    category: str,
    tasks: List[str],
    dry_run: bool = False,
) -> bool:
    """
    将整理后的任务写入 SideNote AI Inbox。

    SideNote 会自动为 AI Inbox 中的每行前添加 ☐ 复选框。

    参数:
        category:  分类名
        tasks:     任务列表
        dry_run:   若为 True，只打印不写入

    返回:
        是否成功写入
    """
    if not tasks:
        print(f"  → 无任务需要写入")
        return False

    inbox_file = ARCHIVE_DIR / f"{category}_ai_append.txt"

    if dry_run:
        print(f"\n  [DRY RUN] 将写入: {inbox_file}")
        print(f"  {'='*40}")
        for t in tasks:
            print(f"  {t}")
        return True

    try:
        with open(inbox_file, "w", encoding="utf-8") as f:
            f.write(INBOX_HEADER + "\n")
            for task in tasks:
                f.write(task + "\n")
        print(f"  ✅ 已写入 {len(tasks)} 项任务 → {inbox_file.name}")
        return True

    except IOError as e:
        print(f"  ❌ 写入失败: {e}")
        return False


# ============================================================
# 辅助函数
# ============================================================

def get_today_str() -> str:
    """获取今天的日期字符串。"""
    return datetime.date.today().strftime("%Y-%m-%d")


def get_yesterday_str() -> str:
    """获取昨天的日期字符串。"""
    return (datetime.date.today() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")


def get_weekday_cn(date_str: str) -> str:
    """获取中文星期几。"""
    weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    dt = datetime.datetime.strptime(date_str, "%Y-%m-%d")
    return weekdays[dt.weekday()]


def print_header(yesterday_str: str, today_str: str):
    """打印美观的头部信息。"""
    weekday_cn = get_weekday_cn(yesterday_str)
    print(f"""
╔═══════════════════════════════════════════════╗
║      SideNote 任务合并整理                     ║
║      昨日: {yesterday_str} 星期{weekday_cn}              ║
║      今日: {today_str}                         ║
╚═══════════════════════════════════════════════╝
""")


# ============================================================
# 主函数
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="SideNote 任务延续 Skill - 昨日未完成 + 今日已有 → LLM 合并整理 → 面板",
    )
    parser.add_argument(
        "--category", "-c",
        choices=CATEGORIES,
        help="只处理指定分类（默认处理所有分类）",
    )
    parser.add_argument(
        "--date", "-d",
        help="指定昨日日期，格式 yyyy-MM-dd（默认自动计算昨天）",
    )
    parser.add_argument(
        "--today-only",
        action="store_true",
        help="只整理今日任务，不处理昨日遗留",
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="预览模式：只显示结果，不写入 Inbox",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="详细输出：显示原始任务内容",
    )

    args = parser.parse_args()

    yesterday_str = args.date if args.date else get_yesterday_str()
    today_str = get_today_str()
    weekday_cn = get_weekday_cn(today_str)

    print_header(yesterday_str, today_str)

    categories = [args.category] if args.category else CATEGORIES
    total_written = 0

    for category in categories:
        label = CATEGORY_LABELS.get(category, category)
        print(f"\n📂 【{label}】({category})")

        # 1. 读取昨日未完成任务
        yesterday_tasks = load_yesterday_unfinished(yesterday_str, category) \
            if not args.today_only else []

        # 2. 读取今日已有任务
        today_tasks = load_today_tasks(today_str, category)

        if not yesterday_tasks and not today_tasks:
            print(f"  📭 无任务需要处理")
            continue

        if args.verbose:
            if yesterday_tasks:
                print(f"  📋 昨日未完成 ({len(yesterday_tasks)} 项):")
                for t in yesterday_tasks:
                    print(f"    ☐ {t}")
            if today_tasks:
                print(f"  📋 今日已有 ({len(today_tasks)} 项):")
                for t in today_tasks:
                    print(f"    {t}")

        # 3. LLM 合并整理
        organized = organize_tasks(
            category,
            yesterday_tasks,
            today_tasks,
            yesterday_str,
            today_str,
            weekday_cn,
        )

        # 4. 写入 AI Inbox
        if write_to_inbox(category, organized, dry_run=args.dry_run):
            total_written += len(organized)

    # 总结
    print(f"\n{'='*50}")
    if args.dry_run:
        print(f"📋 预览完成，以上是将会写入的内容。")
        print(f"   去掉 --dry-run 参数即可实际写入。")
    else:
        print(f"✅ 处理完成！共整理 {total_written} 项任务写入今日面板。")
        print(f"   打开 SideNote 即可查看。")

    return 0


if __name__ == "__main__":
    sys.exit(main())
