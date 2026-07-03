# SideNote 任务延续 Skill — 演示 Demo

> 这是一个给 hermes-agent 看的实现需求说明。请先审阅，确认后再交付给 hermes-agent。

---

## 一、要解决什么问题

SideNote 每天清空面板，昨日未完成的任务就丢了。需要一个 Skill 每天自动：

```
昨日未完成（☐）  ─┐
                  ├─→ LLM 合并整理 → 写入今日面板
今日已有任务       ─┘
```

## 二、路径问题：数据目录在哪里？

SideNote 的数据目录通过「**菜单栏 → SideNote → 打开数据目录**」可以查到。

但脚本需要一个可靠的方式自动定位，有两种做法：

### 做法 A：写死默认路径（推荐 demo 阶段用）

```python
ARCHIVE_DIR = Path.home() / "Documents" / "SideNote_Archive" / "Current_Week"
```

### 做法 B：从配置文件读取（灵活）

```python
import json
config_path = Path.home() / ".config" / "sidenote" / "carryover.json"
# {"archive_dir": "~/Documents/SideNote_Archive/Current_Week"}
```

### 做法 C：让 SideNote 写入一个标记文件

SideNote 源码中 `archiveURL` 在 `~/Library/Application Support/SideNote/Archive/`，可在 app 启动时往固定路径写一个 symlink 或标记文件。

**demo 阶段先用做法 A，后续可以升级。**

## 三、核心代码 Demo

```python
#!/usr/bin/env python3
"""
sidenote_carryover_demo.py — 给 hermes-agent 看的核心逻辑
"""

import os, datetime
from pathlib import Path

ARCHIVE = Path.home() / "Documents" / "SideNote_Archive" / "Current_Week"
DAILY = ARCHIVE / "Daily"

yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
today = datetime.date.today().strftime("%Y-%m-%d")

for cat in ["work", "dev", "life"]:

    # 1. 读昨日未完成
    y_file = DAILY / f"{yesterday}_{cat}.txt"
    yesterday_tasks = []
    if y_file.exists():
        for line in y_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("☐"):
                yesterday_tasks.append(line.replace("☐", "", 1).strip())

    # 2. 读今日已有
    t_file = DAILY / f"{today}_{cat}.txt"
    today_tasks = []
    if t_file.exists():
        for line in t_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("☐"):
                today_tasks.append(f"[待办] {line.replace('☐', '', 1).strip()}")
            elif line.startswith("☑"):
                today_tasks.append(f"[已完成] {line.replace('☑', '', 1).strip()}")

    if not yesterday_tasks and not today_tasks:
        continue

    # 3. 交给 LLM 整理（略 — 见下文提示词）
    # organized = llm_organize(cat, yesterday_tasks, today_tasks)
    organized = yesterday_tasks + [t for t in today_tasks if t.startswith("[待办]")]

    # 4. 写入 AI Inbox
    inbox = ARCHIVE / f"{cat}_ai_append.txt"
    inbox.write_text(
        "--- 昨日遗留 + 今日任务（合并整理）---\n" +
        "\n".join(organized) + "\n",
        encoding="utf-8",
    )

    print(f"[{cat}] 写入 {len(organized)} 项")
```

## 四、LLM 提示词（核心）

把昨日和今日任务拼成一段文本发给 LLM：

```
你是一个待办事项整理助手。

你会收到：
A) 昨天未完成的任务
B) 今天已有的任务（标记了已完成/未完成）

请做：
1. 去重合并 — A 和 B 中相同的任务合并
2. 语义归类 — 用【分组名】做标题
3. 优先级排序 — 紧急重要 > 重要不紧急 > 其他
4. 清晰化重写 — 模糊任务改为可执行句式

特别注意：
- 今天【已完成】的不要再次列出
- 只输出「今天还需要做的事」
- 不要 ☐ 符号，不要编号，不要 AI 说明
```

## 五、输入输出示例

**昨日文件** `2026-04-14_work.txt`：
```
☐ 修复登录页Bug
☐ 修复Safari兼容问题
```

**今日文件** `2026-04-15_work.txt`：
```
☑ 回复邮件
☐ 写周报
```

**LLM 整理后写入 `work_ai_append.txt`**：
```
--- 昨日遗留 + 今日任务（合并整理）---
【Bug修复】
修复登录页在 Safari 下的兼容性问题
【文档】
完成本周工作周报
```

> ☑ 回复邮件 → 今日已打勾 → LLM 自动剔除

---

## 六、给 hermes-agent 的指令

```
实现一个 Python 脚本，每天自动：

1. 读 ~/Documents/SideNote_Archive/Current_Week/Daily/{昨日日期}_{分类}.txt
   提取所有 ☐ 开头的行 → 昨日未完成

2. 读 ~/Documents/SideNote_Archive/Current_Week/Daily/{今日日期}_{分类}.txt
   提取所有行，区分 ☐（未完成）和 ☑（已完成）

3. 两组任务合并发给 LLM（OpenAI 兼容接口）
   原则：去重合并、语义归类、优先级排序、今日已完成的不再列出

4. 结果写入 ~/Documents/SideNote_Archive/Current_Week/{分类}_ai_append.txt
   SideNote 自动添加 ☐ 渲染到面板

5. LLM 不可用时降级：简单合并去重（今日已完成跳过）
   API Key 通过环境变量 SIDENOTE_LLM_API_KEY 传入
```

---

## 七、确认清单

请确认以下设计决策：

- [ ] **数据目录**：默认用 `~/Documents/SideNote_Archive/Current_Week/`，是否需要加配置项？
- [ ] **LLM 模型**：默认 gpt-4o-mini，是否要支持切换？
- [ ] **触发方式**：crontab 每天早上 8:00 执行，还是集成进 SideNote 内部？
- [ ] **已完成任务**：今日已打勾的是否自动剔除？还是保留供参考？
- [ ] **降级策略**：LLM 不可用时简单合并去重，是否接受？
