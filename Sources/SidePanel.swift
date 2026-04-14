import AppKit
import SwiftUI
import Combine

// ==========================================
// 1. 数据存储层 (Data Layer)
// ==========================================
struct RichNote: Codable {
    var rtfData: Data
    var plainText: String
    var updatedAt: Date
}

enum NoteCategory: String, CaseIterable {
    case work = "工作"
    case dev = "个人开发"
    case life = "生活"
    
    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .dev: return "terminal.fill"
        case .life: return "cup.and.saucer.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .work: return .blue
        case .dev: return .primary
        case .life: return .green
        }
    }
    
    var baseFilename: String {
        switch self {
        case .work: return "work"
        case .dev: return "dev"
        case .life: return "life"
        }
    }
}

@MainActor
class NoteManager: ObservableObject {
    @Published var attributedString: NSAttributedString = NSAttributedString(string: "") { 
        didSet { saveSubject.send() } 
    }
    
    private var lastSavedHash: Int = 0
    private let fileURL: URL
    private let textURL: URL
    let baseFilename: String
    
    private var saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    init(category: NoteCategory) {
        self.baseFilename = category.baseFilename
        let currentWeekDir = MaintenanceManager.archiveURL.appendingPathComponent("Current_Week")
        
        self.fileURL = currentWeekDir.appendingPathComponent("notes_\(baseFilename).json")
        self.textURL = currentWeekDir.appendingPathComponent("\(baseFilename).txt")
        
        load()
        checkDailyAndAIUpdates()
        
        saveSubject
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.saveIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    func resetData() {
        self.attributedString = NSAttributedString(string: "")
        UserDefaults.standard.removeObject(forKey: "sidenote_last_day_\(baseFilename)")
    }
    
    func checkDailyAndAIUpdates() {
        let currentWeekDir = MaintenanceManager.archiveURL.appendingPathComponent("Current_Week")
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)
        
        let lastDay = UserDefaults.standard.string(forKey: "sidenote_last_day_\(baseFilename)")
        var modified = false
        
        // 1. 每日清空逻辑 (Daily Reset)
        if lastDay != todayStr {
            self.attributedString = NSAttributedString(string: "")
            UserDefaults.standard.set(todayStr, forKey: "sidenote_last_day_\(baseFilename)")
            modified = true
        }
        
        let mutableAttr = NSMutableAttributedString(attributedString: attributedString)
        
        // 2. 自动摄取 AI 下发的任务指令文件，并转化为可交互的任务复选框
        let aiFile = currentWeekDir.appendingPathComponent("\(baseFilename)_ai_append.txt")
        var aiContentFound = false
        
        if FileManager.default.fileExists(atPath: aiFile.path) {
            if let aiText = try? String(contentsOf: aiFile, encoding: .utf8), !aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                injectTasks(aiText, into: mutableAttr)
                aiContentFound = true
                modified = true
            }
            try? FileManager.default.removeItem(at: aiFile)
        }
        
        // 3. 注入虚拟/Mock 数据 (如果是一天中第一次打开且没有 AI 文件)
        if lastDay != todayStr && !aiContentFound {
            let mockText: String
            switch baseFilename {
            case "work":
                mockText = "整理今日核心工作任务\n检查 MediaAgent 自动化状态\n复盘昨日遗留待办清单"
            case "dev":
                mockText = "Review 侧边笔记代码提交\n优化 UI 触发表层逻辑\n调试 AI 数据流同步接口"
            case "life":
                mockText = "保持每日核心运动 30 分钟\n补充足够水分与健康饮食\n阅读技术博文或书籍 15 分钟"
            default:
                mockText = "开始记录精彩的一天"
            }
            
            let titleAttr = NSAttributedString(string: "今日建议完成的任务：\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 17), 
                .foregroundColor: NSColor.systemGray
            ])
            mutableAttr.append(titleAttr)
            injectTasks(mockText, into: mutableAttr)
            modified = true
        }
        
        if modified {
            self.attributedString = mutableAttr
        }
    }
    
    /// 辅助方法：将纯文本任务段落转化为带 ☐ 的富文本
    private func injectTasks(_ text: String, into mutableAttr: NSMutableAttributedString) {
        let rootFont = NSFont.systemFont(ofSize: 16)
        let processedText = text.components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }
                if !trimmed.hasPrefix("☐") && !trimmed.hasPrefix("☑") {
                   let regex = try? NSRegularExpression(pattern: "^\\d+\\.\\s*")
                   let cleanRange = NSRange(location: 0, length: trimmed.utf16.count)
                   let stripped = regex?.stringByReplacingMatches(in: trimmed, range: cleanRange, withTemplate: "") ?? trimmed
                   return "☐ " + stripped
                }
                return line
            }
            .joined(separator: "\n")
        
        let aiAttr = NSAttributedString(string: "\(processedText)\n\n", attributes: [.font: rootFont, .foregroundColor: NSColor.black])
        mutableAttr.append(aiAttr)
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let note = try? JSONDecoder().decode(RichNote.self, from: data),
              let attr = try? NSAttributedString(data: note.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            return
        }
        
        let mutableAttr = NSMutableAttributedString(attributedString: attr)
        let fullRange = NSRange(location: 0, length: mutableAttr.length)
        mutableAttr.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if let color = value as? NSColor {
                if color != .systemRed && color != .systemBlue && color != .systemGreen && color != .systemPurple && color != .systemGray {
                    mutableAttr.addAttribute(.foregroundColor, value: NSColor.black, range: range)
                }
            } else {
                mutableAttr.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            }
        }
        mutableAttr.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: fullRange)
        
        self.attributedString = mutableAttr
        self.lastSavedHash = mutableAttr.hashValue
    }
    
    private func saveIfNeeded() {
        let currentHash = attributedString.hashValue
        guard currentHash != lastSavedHash else { return }
        lastSavedHash = currentHash
        
        let rtfData = try? attributedString.data(from: NSRange(location: 0, length: attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let plainText = attributedString.string
        
        let note = RichNote(rtfData: rtfData ?? Data(), plainText: plainText, updatedAt: Date())
        if let data = try? JSONEncoder().encode(note) { 
            try? data.write(to: fileURL) 
        }
        
        // 1. 同步输出本周全量明文 (Weekly All - 在 Daily Slate 模式下，此文件主要体现最新状态)
        try? plainText.write(to: textURL, atomically: true, encoding: .utf8)
        
        // 2. 同步输出绝对每日切片 (Daily Slices)
        let dailyDir = MaintenanceManager.archiveURL.appendingPathComponent("Current_Week/Daily")
        try? FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // 使用 UserDefaults 中的日期确保文件名准确
        let dateStr = UserDefaults.standard.string(forKey: "sidenote_last_day_\(baseFilename)") ?? formatter.string(from: Date())
        
        let dailyURL = dailyDir.appendingPathComponent("\(dateStr)_\(baseFilename).txt")
        try? plainText.write(to: dailyURL, atomically: true, encoding: .utf8)
    }
}

// ==========================================
// 2. 窗口控制器层 (Window Management)
// ==========================================
@MainActor
class SidePanelController: NSObject, ObservableObject {
    var panel: SidePanel?
    @Published var isExpanded = false
    @Published var isHovered = false
    
    let workNotes = NoteManager(category: .work)
    let devNotes = NoteManager(category: .dev)
    let lifeNotes = NoteManager(category: .life)
    
    var activeTextView: NSTextView?
    var activeNoteManager: NoteManager?
    @Published var activeCategory: NoteCategory?
    
    private var cancellables = Set<AnyCancellable>()
    
    func setupPanel() {
        let screenRect = NSScreen.main?.visibleFrame ?? .zero
        let p = SidePanel(contentRect: NSRect(x: screenRect.minX, y: screenRect.minY, width: 12, height: screenRect.height), backing: .buffered, defer: false)
        
        p.onSwipeRight = { [weak self] in self?.isExpanded = true }
        p.onSwipeLeft = { [weak self] in self?.isExpanded = false }
        p.onEscape = { [weak self] in self?.isExpanded = false }
        
        self.panel = p
        let rootView = SideView(ctrl: self).colorScheme(.light)
        p.contentView = NSHostingView(rootView: rootView)
        p.makeKeyAndOrderFront(nil)
        
        $isExpanded.sink { [weak self] exp in 
            guard let self = self else { return }
            if exp {
                if MaintenanceManager.performCheck() {
                    self.workNotes.resetData()
                    self.devNotes.resetData()
                    self.lifeNotes.resetData()
                }
                self.workNotes.checkDailyAndAIUpdates()
                self.devNotes.checkDailyAndAIUpdates()
                self.lifeNotes.checkDailyAndAIUpdates()
            }
        }.store(in: &cancellables)
        
        $isExpanded.combineLatest($isHovered).sink { [weak self] (exp, hov) in 
            self?.updatePanelFrame(isExpanded: exp, isHovered: hov) 
        }.store(in: &cancellables)
    }
    
    private func updatePanelFrame(isExpanded: Bool, isHovered: Bool) {
        guard let p = panel, let s = NSScreen.main?.visibleFrame else { return }
        let targetWidth: CGFloat = isExpanded ? 340 : (isHovered ? 24 : 12)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15 
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(NSRect(x: s.minX, y: s.minY, width: targetWidth, height: s.height), display: true)
        }
    }
    
    func applyColorToSelection(_ color: NSColor) {
        guard let tv = activeTextView, let nm = activeNoteManager else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            tv.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
            tv.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: range)
            nm.attributedString = tv.attributedString()
        }
    }
}

class SidePanel: NSPanel {
    var onSwipeRight: (() -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onEscape: (() -> Void)?
    
    private var accumulatedDeltaX: CGFloat = 0
    private let swipeThreshold: CGFloat = 10.0 
    
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .borderless], backing: backing, defer: flag)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.hasShadow = true
        self.becomesKeyOnlyIfNeeded = false
        self.appearance = NSAppearance(named: .aqua)
    }
    
    override var canBecomeKey: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if abs(dx) > abs(dy) * 0.8 {
                accumulatedDeltaX += dx
                if dx > 8 || accumulatedDeltaX > swipeThreshold {
                    onSwipeRight?()
                    accumulatedDeltaX = 0
                } else if dx < -5 || accumulatedDeltaX < -swipeThreshold {
                    onSwipeLeft?()
                    accumulatedDeltaX = 0
                }
                return 
            }
            if event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled {
                accumulatedDeltaX = 0
            }
        }
        if event.type == .keyDown && event.keyCode == 53 { 
            onEscape?()
            return 
        }
        super.sendEvent(event)
    }
}

// ==========================================
// 3. 富文本组件层与自定义鼠标追踪器 (AppKit Text View Integration)
// ==========================================
class NativeInteractiveTextView: NSTextView {
    // 焦点获取回调
    var onFocusGained: (() -> Void)?
    
    override func becomeFirstResponder() -> Bool {
        let success = super.becomeFirstResponder()
        if success {
            onFocusGained?()
        }
        return success
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        var fraction: CGFloat = 0.0
        
        if let layoutManager = self.layoutManager, let textContainer = self.textContainer {
            let charIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
            if let textStorage = self.textStorage, charIndex < textStorage.length {
                let clickedChar = (textStorage.string as NSString).substring(with: NSRange(location: charIndex, length: 1))
                if clickedChar == "☐" || clickedChar == "☑" {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    let hitRect = rect.insetBy(dx: -4, dy: -4)
                    if hitRect.contains(point) {
                        let replacement = (clickedChar == "☐") ? "☑" : "☐"
                        textStorage.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: replacement)
                        self.didChangeText() 
                        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self) 
                        return
                    }
                }
            }
        }
        
        super.mouseDown(with: event)
        // 确保点击区域时实时上报焦点变更
        onFocusGained?()
    }
}

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var ctrl: SidePanelController
    @ObservedObject var noteManager: NoteManager
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true
        
        let originalTextView = scrollView.documentView as! NSTextView
        let customTextView = NativeInteractiveTextView(frame: originalTextView.frame)
        customTextView.minSize = originalTextView.minSize
        customTextView.maxSize = originalTextView.maxSize
        customTextView.isVerticallyResizable = originalTextView.isVerticallyResizable
        customTextView.isHorizontallyResizable = originalTextView.isHorizontallyResizable
        customTextView.autoresizingMask = originalTextView.autoresizingMask
        customTextView.textContainer?.containerSize = originalTextView.textContainer!.containerSize
        customTextView.textContainer?.widthTracksTextView = true
        
        // 当文本框被点击或成为第一响应者时，进行精准、绝对可靠的聚光灯对焦！
        customTextView.onFocusGained = {
            DispatchQueue.main.async {
                context.coordinator.parent.ctrl.activeTextView = customTextView
                context.coordinator.parent.ctrl.activeNoteManager = context.coordinator.parent.noteManager
                
                if context.coordinator.parent.noteManager === context.coordinator.parent.ctrl.workNotes {
                    context.coordinator.parent.ctrl.activeCategory = .work
                } else if context.coordinator.parent.noteManager === context.coordinator.parent.ctrl.devNotes {
                    context.coordinator.parent.ctrl.activeCategory = .dev
                } else if context.coordinator.parent.noteManager === context.coordinator.parent.ctrl.lifeNotes {
                    context.coordinator.parent.ctrl.activeCategory = .life
                }
            }
        }
        
        scrollView.documentView = customTextView
        
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        
        textView.isEditable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        
        textView.appearance = NSAppearance(named: .aqua)
        textView.textColor = .black
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.insertionPointColor = .black
        textView.typingAttributes[.foregroundColor] = NSColor.black
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 16)
        
        textView.textStorage?.setAttributedString(noteManager.attributedString)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if !tv.attributedString().isEqual(to: noteManager.attributedString) {
            tv.textStorage?.setAttributedString(noteManager.attributedString)
            tv.typingAttributes[.foregroundColor] = NSColor.black 
            tv.typingAttributes[.font] = NSFont.systemFont(ofSize: 16)
        }
        tv.insertionPointColor = .black 
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.noteManager.attributedString = tv.attributedString()
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let color = tv.typingAttributes[.foregroundColor] as? NSColor
            
            if color != .systemRed && color != .systemBlue && color != .systemGreen && color != .systemPurple && color != .systemGray {
                tv.typingAttributes[.foregroundColor] = NSColor.black
            }
            tv.typingAttributes[.font] = NSFont.systemFont(ofSize: 16)
            // 焦点变更已移交至 onFocusGained 捕捉，更底层且绝对可靠
        }
    }
}

struct AreaView: View {
    let category: NoteCategory
    @ObservedObject var ctrl: SidePanelController
    @ObservedObject var noteManager: NoteManager
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .foregroundColor(category.color)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            RichTextEditor(ctrl: ctrl, noteManager: noteManager)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle()) // 确保空白处也能点击
        .onTapGesture {
            // 点击整个区域（包括标题）时，立刻强制切换焦点
            ctrl.activeCategory = category
            ctrl.activeNoteManager = noteManager
        }
        .opacity(ctrl.activeCategory == nil || ctrl.activeCategory == category ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.2), value: ctrl.activeCategory)
    }
}

// ==========================================
// 4. SwiftUI 界面层 (View Layer)
// ==========================================
struct SideView: View {
    @ObservedObject var ctrl: SidePanelController
    
    var body: some View {
        HStack(spacing: 0) {
            if ctrl.isExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        let avatarImage: NSImage = {
                            if let path = Bundle.main.path(forResource: "avatar", ofType: "png"),
                               let img = NSImage(contentsOfFile: path) {
                                return img
                            }
                            return NSImage()
                        }()
                        
                        Image(nsImage: avatarImage)
                            .resizable().scaledToFit().frame(width: 28, height: 28).clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("侧边笔记").font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(Date(), style: .date).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { ctrl.isExpanded = false }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                    
                    Divider().padding(.horizontal, 12).padding(.bottom, 4)
                    
                    VStack(spacing: 0) {
                        AreaView(category: .work, ctrl: ctrl, noteManager: ctrl.workNotes)
                        Divider().padding(.horizontal, 16).padding(.vertical, 4)
                        AreaView(category: .dev, ctrl: ctrl, noteManager: ctrl.devNotes)
                        Divider().padding(.horizontal, 16).padding(.vertical, 4)
                        AreaView(category: .life, ctrl: ctrl, noteManager: ctrl.lifeNotes)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    HStack(spacing: 20) {
                        ColorButton(color: .red, action: { ctrl.applyColorToSelection(NSColor.systemRed) })
                        ColorButton(color: .blue, action: { ctrl.applyColorToSelection(NSColor.systemBlue) })
                        ColorButton(color: .green, action: { ctrl.applyColorToSelection(NSColor.systemGreen) })
                        ColorButton(color: .primary, action: { ctrl.applyColorToSelection(NSColor.black) }, isClear: true)
                        Spacer()
                    }.padding(.horizontal, 24).padding(.vertical, 16)
                }
                .frame(width: 330)
                .background(Color(red: 0.88, green: 0.98, blue: 1.0).clipShape(RightRoundedShape(radius: 20)))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 5, y: 0)
                .transition(.move(edge: .leading))
            }
            
            VStack(spacing: 0) {
                Spacer().frame(height: 120) // 顶部死区：避免与全屏控制按钮冲突
                
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.001)
                        .frame(width: ctrl.isExpanded ? 0 : 55)
                        .onHover { over in ctrl.isHovered = over }
                        .onTapGesture { ctrl.isExpanded = true }
                    
                    if !ctrl.isExpanded {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ctrl.isHovered ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 4, height: 60).padding(.leading, 4)
                    }
                }
                
                Spacer() // 底部撑开
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onChange(of: ctrl.isExpanded) { isExp in
            if isExp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ctrl.panel?.makeKey()
                }
            }
        }
    }
}

struct ColorButton: View {
    let color: Color
    let action: () -> Void
    var isClear = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isClear { Image(systemName: "pencil.slash").font(.system(size: 10)).foregroundColor(.secondary) }
                Circle().fill(color).frame(width: 18, height: 18).overlay(Circle().stroke(Color.white, lineWidth: 2)).shadow(radius: 1).opacity(isClear ? 0.3 : 1.0)
            }
        }.buttonStyle(.plain)
    }
}

// 辅助组件：引入 macOS 原生的毛玻璃模糊材质
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct RightRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
