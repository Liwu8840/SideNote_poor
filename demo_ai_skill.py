import os

# ==============================================================
# 演示: AI Agent 如何读取昨天遗漏的任务，并回写给今天的面板
# 建议通过 cron 或者大模型调度平台每天早上 8:00 自动执行一次
# ==============================================================

# 1. 确定目录
ARCHIVE_DIR = os.path.expanduser("~/Documents/SideNote_Archive/Current_Week/")
DAILY_DIR = os.path.join(ARCHIVE_DIR, "Daily")

def process_daily_tasks(category_name):
    """
    category_name 可以是 'work', 'dev', 'life'
    """
    # 比如你想读取昨天的文件：
    # 实际应用中可以用 datetime 获取昨天的日期，这里假设你需要读取 2026-04-13 的：
    target_date = "2026-04-13" 
    daily_file = os.path.join(DAILY_DIR, f"{target_date}_{category_name}.txt")
    
    if not os.path.exists(daily_file):
        print(f"[{category_name}] 未找到 {target_date} 的记录文件")
        return
        
    with open(daily_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    unfinished_tasks = []
    
    for line in lines:
        line = line.strip()
        # 核心逻辑：AI 寻找含有空黑框的字符即代表用户未完成的任务
        if line.startswith("☐"):
            # 提取具体的任务文本内容 (去除前面的框和空格)
            task_content = line.replace("☐", "").strip()
            unfinished_tasks.append(task_content)
            
    if unfinished_tasks:
        print(f"在 {category_name} 模块中，发现 {len(unfinished_tasks)} 项未完成的任务。")
        
        # ----------------------------------------------------
        # 2. 调用大模型对未完成任务进行润色或者整理（略），或者直接重抛给今天
        # 下面演示将未完成的任务直接重新“投递”给今天的界面作为遗留提醒
        # ----------------------------------------------------
        inbox_file = os.path.join(ARCHIVE_DIR, f"{category_name}_ai_append.txt")
        
        with open(inbox_file, 'w', encoding='utf-8') as out:
            for task in unfinished_tasks:
                # 注意：AI写入时不需要带框！
                # 只要写入干干净净的纯文本即可。
                # SideNote 在吞入时会自动判断并强制补齐 `☐` 方框让用户可以勾选！
                out.write(task + "\n")
                
        print(f" ---> 成功将积压任务发往 {category_name} 吞噬槽，等待 SideNote 被唤醒吞入...")

if __name__ == "__main__":
    for cat in ["work", "dev", "life"]:
        process_daily_tasks(cat)
