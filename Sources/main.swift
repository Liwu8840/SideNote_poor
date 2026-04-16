import AppKit
import ServiceManagement

@MainActor
class LoginItemManager {
    static let shared = LoginItemManager()
    private let appName = "侧边笔记"
    
    func isEnabled() -> Bool {
        // 先尝试通过现代 SMAppService 检测 (针对已签名的正式包)
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        
        // 兜底方案：检测 System Events 里的登录项 (针对本地开发的未签名包)
        let script = "tell application \"System Events\" to get name of every login item"
        guard let output = runAppleScript(script) else { return false }
        return output.contains(appName) || output.contains("SideNote")
    }
    
    func setEnabled(_ enabled: Bool) {
        // 1. 尝试现代方式 (即便失败也继续)
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled { try service.register() }
                else { try service.unregister() }
            } catch {
                print("SMAppService failed, falling back to AppleScript: \(error)")
            }
        }
        
        // 2. 苹果脚本兜底 (最可靠的本地通用方案)
        if enabled {
            let appPath = Bundle.main.bundlePath
            let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false, name:\"\(appName)\"}"
            _ = runAppleScript(script)
        } else {
            let script = "tell application \"System Events\" to delete (every login item whose name is \"\(appName)\" or name is \"SideNote\")"
            _ = runAppleScript(script)
        }
    }
    
    private func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript Error: \(err)")
                return nil
            }
            return output.stringValue
        }
        return nil
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = SidePanelController()
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // Ensure root structure is ready before any Panel operations
        _ = MaintenanceManager.performCheck()
        
        panelController.setupPanel()
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusBar()
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "SideNote")
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "展示/隐藏面板", action: #selector(togglePanel), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        
        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = LoginItemManager.shared.isEnabled() ? .on : .off
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem(title: "  └─ 在系统设置中管理...", action: #selector(openLoginItemsSettings), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "完全退出 侧边笔记", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func togglePanel() {
        panelController.isExpanded.toggle()
        if panelController.isExpanded { 
            panelController.panel?.makeKeyAndOrderFront(nil) 
        }
    }
    
    @objc func toggleLogin(_ sender: NSMenuItem) {
        let currentlyEnabled = LoginItemManager.shared.isEnabled()
        LoginItemManager.shared.setEnabled(!currentlyEnabled)
        sender.state = (!currentlyEnabled) ? .on : .off
    }
    
    @objc func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

struct MaintenanceManager {
    /// 获取标准的 Application Support 目录下的 SideNote 存档路径
    /// 打包后的 app 会使用 ~/Library/Application Support/SideNote/Archive
    static let archiveURL: URL = {
        let appSupportURL: URL
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupportURL = url
        } else {
            // Fallback to home directory
            appSupportURL = FileManager.default.homeDirectoryForCurrentUser
        }
        return appSupportURL.appendingPathComponent("SideNote/Archive")
    }()
    
    static var currentWeekURL: URL { archiveURL.appendingPathComponent("Current_Week") }
    
    
    /// 获取 AI 指令文件路径（供外部工具使用）
    static func getAIFilePaths() -> [String: URL] {
        let currentWeekDir = currentWeekURL
        return [
            "work_replace": currentWeekDir.appendingPathComponent("work_ai_replace.txt"),
            "work_append": currentWeekDir.appendingPathComponent("work_ai_append.txt"),
            "dev_replace": currentWeekDir.appendingPathComponent("dev_ai_replace.txt"),
            "dev_append": currentWeekDir.appendingPathComponent("dev_ai_append.txt"),
            "life_replace": currentWeekDir.appendingPathComponent("life_ai_replace.txt"),
            "life_append": currentWeekDir.appendingPathComponent("life_ai_append.txt"),
            "archive_root": archiveURL,
            "current_week": currentWeekDir
        ]
    }
    
    static func performCheck() -> Bool {
        // 直接创建目录结构（不迁移旧数据）
        try? FileManager.default.createDirectory(at: currentWeekURL, withIntermediateDirectories: true)
        
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday start
        
        let now = Date()
        let year = calendar.component(.yearForWeekOfYear, from: now)
        let week = calendar.component(.weekOfYear, from: now)
        let currentWeekID = "\(year)-W\(String(format: "%02d", week))"
        let lastWeekID = UserDefaults.standard.string(forKey: "sidenote_current_week") ?? currentWeekID
        
        if currentWeekID != lastWeekID {
            // Need wipe for new week
            let backupURL = archiveURL.appendingPathComponent("Backup_\(lastWeekID)")
            try? FileManager.default.copyItem(at: currentWeekURL, to: backupURL)
            try? FileManager.default.removeItem(at: currentWeekURL)
            try? FileManager.default.createDirectory(at: currentWeekURL, withIntermediateDirectories: true)
            UserDefaults.standard.set(currentWeekID, forKey: "sidenote_current_week")
            return true // Week changed, wipe local UI state
        } else {
            UserDefaults.standard.set(currentWeekID, forKey: "sidenote_current_week")
            return false
        }
    }
}

// Workaround for @MainActor initialization
let delegate: AppDelegate = MainActor.assumeIsolated {
    AppDelegate()
}
let app = NSApplication.shared
app.delegate = delegate
app.run()
