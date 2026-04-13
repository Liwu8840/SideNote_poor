# SideNote

SideNote 是一个用 Swift、AppKit 和 SwiftUI 写的原生 macOS 侧边栏记事本。它常驻在屏幕边缘，提供 `工作`、`开发`、`生活` 三个长期可用的面板，并支持通过纯文本文件和 AI / Agent 工作流对接。

[English README](README.md) | [AI 接口文档](AI_INTEGRATION.zh.md) | [打包说明](PACKAGING.zh.md)

## 功能特性

- 三个固定分类面板：`Work`、`Dev`、`Life`
- 屏幕边缘呼出与收起的侧边栏交互
- 自动按周归档到 `~/Documents/SideNote_Archive`
- 自动导出本周全文和按日切片文本
- 支持 AI Inbox 文本投递并自动转为待办事项
- 菜单栏控制和开机自启动开关

## 运行要求

- macOS 13 及以上
- Swift 6 工具链，或支持 Swift Package Manager 的 Xcode

## 构建运行

```bash
swift build
swift run
```

## 打包文件

仓库内提供了已经打包好的应用压缩包：

- `SideNote.app.zip`

如果你想重新自己打包，可以直接执行：

```bash
./package.sh
```

详细说明见 [PACKAGING.zh.md](PACKAGING.zh.md)。

## 项目结构

- `Sources/main.swift`：应用启动、菜单栏与生命周期
- `Sources/SidePanel.swift`：侧边栏 UI、笔记存储与归档逻辑
- `demo_ai_skill.py`：AI 工作流接入示例脚本

## 数据与 AI 接入

SideNote 的工作数据目录是：

```text
~/Documents/SideNote_Archive/Current_Week/
```

应用会输出每周纯文本、每日切片，并监听 `work_ai_append.txt`、`dev_ai_append.txt`、`life_ai_append.txt` 这类 AI 投递文件。

完整的中文 AI 接口说明见 [AI_INTEGRATION.zh.md](AI_INTEGRATION.zh.md)。
