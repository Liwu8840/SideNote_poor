# SideNote 应用程序打包与图标生效指南

如果你需要手动打包应用，或者发现图标没有正常显示，请参考本手册。

## 1. 自动化打包脚本 (package.sh)

在项目根目录下，你可以创建一个 `package.sh` 文件并运行它。以下是完整的打包逻辑：

```bash
#!/bin/bash

# 1. 编译最新的二进制文件 (Release 模式)
swift build -c release

# 2. 创建 macOS App 目录结构
APP_NAME="SideNote.app"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# 3. 复制图标 (关键：放入 Resources 并命名为 AppIcon.icns)
# 如果你已经有了 SideNote.icns，直接复制并改名
cp SideNote.icns "$APP_NAME/Contents/Resources/AppIcon.icns"

# 4. 复制二进制文件
cp .build/release/SideNote "$APP_NAME/Contents/MacOS/SideNote"

# 5. 生成 Info.plist (这是 App 的大脑)
cat <<EOF > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SideNote</string>
    <key>CFBundleIdentifier</key>
    <string>com.liwu.SideNote</string>
    <key>CFBundleName</key>
    <string>SideNote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 6. 强制系统刷新图标缓存
touch "$APP_NAME"
echo "打包完成！请尝试运行 $APP_NAME"
```

---

## 2. 如果图标还是不起作用？(排查与修复)

macOS 的图标刷新机制非常顽固，如果你的 `SideNote.app` 显示的还是文件夹图标，请依次尝试以下操作：

### 方案 A：物理位移法（最有效）
将 `SideNote.app` **从当前文件夹拖到桌面上，然后再拖回来**。
> **原理**：更改文件路径会强制系统的 Finder 进程重新读取应用的 `Info.plist` 和图标资源。

### 方案 B：清除属性缓存
在终端运行：
```bash
xattr -rc SideNote.app
```
> **原理**：清除下载/属性标记，强制 Finder 刷新元数据。

### 方案 C：强制重启 Finder
按住键键盘上的 `Option (Alt)` 键，同时右键点击左下方的 Finder 图标，选择 **「重新开启 (Relaunch)」**。

---

## 3. 图标文件格式说明
- 源代码位置：`SideNote.icns`
- App 内部位置：`SideNote.app/Contents/Resources/AppIcon.icns`
- 注意：`Info.plist` 中的 `CFBundleIconFile` 填写的名称不需要带 `.icns` 后缀。
