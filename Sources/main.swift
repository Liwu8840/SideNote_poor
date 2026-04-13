import AppKit
import ServiceManagement

struct MaintenanceManager {
    static let archiveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SideNote_Archive")
    static var currentWeekURL: URL { archiveURL.appendingPathComponent("Current_Week") }
    
    static func performCheck() -> Bool {
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
        if SMAppService.mainApp.status == .enabled {
             loginItem.state = .on
        } else {
             loginItem.state = .off
        }
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "完全退出 SideNote", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func togglePanel() {
        panelController.isExpanded.toggle()
        if panelController.isExpanded { 
            panelController.panel?.makeKeyAndOrderFront(nil) 
        }
    }
    
    @objc func toggleLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
            sender.state = .off
        } else {
            try? service.register()
            sender.state = .on
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
