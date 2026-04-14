//
//  AIAgentSettings.swift
//  DynamicIsland
//
//  Split from SettingsView.swift
//
import SwiftUI
import Defaults
import UniformTypeIdentifiers
import AppKit

struct AIAgentSettings: View {
    @Default(.enableAIAgentFeature) var enableAIAgentFeature
    @Default(.aiAgentShowSneakPeek) var aiAgentShowSneakPeek
    @Default(.aiAgentSoundEffectsEnabled) var aiAgentSoundEffectsEnabled
    @Default(.aiAgentCardFontScale) var aiAgentCardFontScale
    @Default(.aiAgentCardExpandedMaxHeight) var aiAgentCardExpandedMaxHeight
    @Default(.aiAgentIconSelections) private var aiAgentIconSelections
    @Default(.customAppIcons) private var customAppIcons
    @Default(.aiAgentExpandedRetentionSeconds) var aiAgentExpandedRetentionSeconds
    @Default(.aiAgentAutoCleanupMinutes) var aiAgentAutoCleanupMinutes
    @Default(.aiAgentChatDisplayMode) var aiAgentChatDisplayMode
    @Default(.aiAgentShowThinkingBlocks) var aiAgentShowThinkingBlocks
    @Default(.aiAgentShowToolDetails) var aiAgentShowToolDetails
    @Default(.aiAgentShowToolOutput) var aiAgentShowToolOutput
    @Default(.aiAgentExpandedMaxHeightFraction) var aiAgentExpandedMaxHeightFraction
    @Default(.aiAgentThemeMode) private var themeMode
    @Default(.aiAgentCardTheme) private var cardTheme
    @Default(.aiAgentUniformAccentColor) private var uniformAccentColor
    @Default(.aiAgentCustomConfigDirs) private var aiAgentCustomConfigDirs
    @ObservedObject var agentManager = AIAgentManager.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @State private var isConfiguring = false
    @State private var isIconImporterPresented = false
    @State private var iconImportError: String?
    @State private var previewSessions = AIAgentSettings.makePreviewSessions()

    private func highlightID(_ title: String) -> String {
        SettingsTab.aiAgent.highlightID(for: title)
    }

    private var displayedAgents: [AIAgentManager.DetectedAgent] {
        var agents = agentManager.hookConfig.detectedAgents
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if !agents.contains(where: { $0.id == "codex" }) {
            let codexDir = (home as NSString).appendingPathComponent(".codex")
            let codexHooks = (home as NSString).appendingPathComponent(".codex/hooks.json")
            agents.append(
                AIAgentManager.DetectedAgent(
                    id: "codex",
                    displayName: "Codex CLI",
                    settingsPath: codexHooks,
                    configDirExists: FileManager.default.fileExists(atPath: codexDir),
                    settingsFileExists: FileManager.default.fileExists(atPath: codexHooks),
                    hookStatus: .notConfigured
                )
            )
        }

        let sortOrder: [String: Int] = [
            "codebuddy": 0,
            "codex": 1,
            "claude-code": 2,
            "workbuddy": 3,
            "cursor": 4,
            "gemini-cli": 5,
        ]

        return agents.sorted { lhs, rhs in
            let l = sortOrder[lhs.id] ?? 999
            let r = sortOrder[rhs.id] ?? 999
            if l == r { return lhs.displayName < rhs.displayName }
            return l < r
        }
    }

    private var previewStyle: AIAgentCardStyle {
        AIAgentCardStyle(
            fontScale: CGFloat(aiAgentCardFontScale),
            expandedContentMaxHeight: CGFloat(aiAgentCardExpandedMaxHeight),
            theme: ResolvedCardTheme(from: cardTheme)
        )
    }

    private var presetOptions: [(name: String, theme: AIAgentCardTheme)] {
        [
            ("Default", .defaultTheme),
            ("Minimal", .minimal),
            ("Vivid", .vivid),
            ("Monochrome", .monochrome),
            ("Neon", .neon),
            ("Terminal", .terminal),
        ]
    }

    private func isPresetSelected(_ theme: AIAgentCardTheme) -> Bool {
        cardTheme.cardBackgroundOpacity == theme.cardBackgroundOpacity
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAIAgentFeature) {
                    Text("启用 AI 助手监控")
                }
                .settingsHighlight(id: highlightID("Enable AI Agent Monitoring"))
            } header: {
                Text("通用")
            } footer: {
                Text("在灵动岛中监控 AI 编程助手（CodeBuddy、Codex CLI、Claude Code 等）。启用后点击下方的「一键配置」即可自动设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableAIAgentFeature {
                // MARK: Status
                Section {
                    HStack {
                        Text("套接字服务")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(agentManager.isListening ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(agentManager.isListening ? "运行中" : "已停止")
                                .font(.system(size: 12))
                                .foregroundStyle(agentManager.isListening ? .green : .red)
                        }
                    }

                    HStack {
                        Text("活动会话")
                        Spacer()
                        Text("\(agentManager.activeSessionCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let error = agentManager.lastError {
                        HStack {
                            Text("最近错误")
                            Spacer()
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("状态")
                }

                // MARK: AI 助手管理 (Unified)
                Section {
                    // Bridge script status
                    HStack {
                        Image(systemName: agentManager.hookConfig.bridgeInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(agentManager.hookConfig.bridgeInstalled ? .green : .red)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("桥接脚本")
                                .font(.system(size: 12, weight: .medium))
                            Text(agentManager.hookConfig.bridgeInstalled ? "已安装于 ~/.vland/bin/vland-bridge" : "未安装")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Unified agent management cards
                    ForEach(displayedAgents) { agent in
                        agentManagementCard(agent)
                    }

                    // One-click configure all
                    Button(action: {
                        isConfiguring = true
                        agentManager.autoConfigureAll()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isConfiguring = false
                        }
                    }) {
                        HStack {
                            if isConfiguring {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Image(systemName: "wand.and.stars")
                            Text("一键配置")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(isConfiguring)

                    // Refresh detection
                    Button(action: { agentManager.detectInstalledAgents() }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新检测")
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("AI 助手管理")
                } footer: {
                    Text("统一管理 AI 助手的配置状态、图标和目录。目录支持自定义路径（以 . 开头的隐藏目录也可选择）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Configuration Log
                if !agentManager.hookConfig.configurationLog.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(agentManager.hookConfig.configurationLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } header: {
                        Text("配置日志")
                    }
                }

                // MARK: Interaction Reply
                Section {
                    HStack {
                        Text("回复提交")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accessibilityPermission.isAuthorized ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(accessibilityPermission.isAuthorized ? "就绪" : "部分可用")
                                .font(.system(size: 12))
                                .foregroundStyle(accessibilityPermission.isAuthorized ? .green : .orange)
                        }
                    }

                    if !accessibilityPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "启用辅助功能以支持一键提交",
                            message: "审批操作通过桥接脚本直接回传，无需额外权限。但助手提问的回复需要辅助功能权限来自动粘贴并提交到终端窗口，否则仅复制到剪贴板，需手动粘贴。",
                            icon: "hand.raised.fill",
                            iconColor: .orange,
                            requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                            openSettingsAction: { accessibilityPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    Text("交互回复")
                } footer: {
                    Text("审批操作通过桥接脚本直接回传，无需辅助功能权限。助手提问的回复在桥接不可用时，需通过辅助功能自动粘贴提交；未授权则仅复制到剪贴板。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Defaults.Toggle(key: .aiAgentShowSneakPeek) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示 SneakPeek 通知")
                            Text("会话启动或提交新任务时，在灵动岛中短暂显示助手活动。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Show SneakPeek notifications"))

                    Defaults.Toggle(key: .aiAgentSoundEffectsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("播放 8-bit 音效")
                            Text("为会话启动、提交提示、完成和输入请求添加简短的芯片音效提示。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Play 8-bit sound effects"))
                } header: {
                    Text("通知与音效")
                }

                // MARK: Chat Display Mode
                Section {
                    Picker(selection: $aiAgentChatDisplayMode) {
                        ForEach(AIAgentChatMode.allCases) { mode in
                            HStack(spacing: 6) {
                                Image(systemName: mode == .compact ? "list.bullet" : "text.bubble.fill")
                                Text(mode == .compact ? "精简模式" : "详细模式")
                            }
                            .tag(mode)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("聊天显示模式")
                            Text("精简模式：5 轮对话 + 工具调用列表；详细模式：完整对话记录 + Markdown 渲染。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Defaults.Toggle(key: .aiAgentShowThinkingBlocks) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示思考过程")
                            Text("在详细模式中显示 AI 的思考（thinking）内容块。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Defaults.Toggle(key: .aiAgentShowToolDetails) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示工具调用详情")
                            Text("在详细模式中显示工具调用的名称和参数。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Defaults.Toggle(key: .aiAgentShowToolOutput) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示工具输出")
                            Text("在详细模式中显示工具执行的返回结果。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("聊天显示")
                } footer: {
                    Text("详细模式仅支持 CodeBuddy、Claude Code 和 Codex。其他助手始终使用精简模式。详细模式下首次展开时会读取本地 transcript 文件以加载完整历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("卡片字号")
                            Spacer()
                            Text("\(Int(12 * aiAgentCardFontScale)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .settingsHighlight(id: highlightID("Card font size"))

                        Slider(value: $aiAgentCardFontScale, in: 0.85...1.45, step: 0.05)

                        HStack {
                            Text("卡片最大高度")
                            Spacer()
                            Text("\(Int(aiAgentCardExpandedMaxHeight)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .settingsHighlight(id: highlightID("Card max height"))

                        Slider(value: $aiAgentCardExpandedMaxHeight, in: 140...420, step: 10)
                    }
                } header: {
                    Text("卡片布局")
                } footer: {
                    Text("这些控件同时更新实时 AI 助手标签页和下方预览。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Mode Picker
                        Picker("颜色模式", selection: $themeMode) {
                            Text("跟随助手").tag(AIAgentThemeMode.perAgent)
                            Text("统一颜色").tag(AIAgentThemeMode.uniform)
                        }
                        .pickerStyle(.segmented)

                        // Uniform Color Picker (only when uniform mode)
                        if themeMode == .uniform {
                            ColorPicker("统一主题色", selection: $uniformAccentColor)
                        }

                        // Preset Cards
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(presetOptions, id: \.name) { preset in
                                    PresetCardView(
                                        name: preset.name,
                                        theme: preset.theme,
                                        isSelected: isPresetSelected(preset.theme)
                                    ) {
                                        cardTheme = preset.theme
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("卡片主题")
                } footer: {
                    Text("预设定义卡片背景、边框、文字和间距的默认值。选择预设后可单独调整各参数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("展开最大高度")
                            Spacer()
                            Text("\(Int(aiAgentExpandedMaxHeightFraction * 100))% of screen")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .settingsHighlight(id: highlightID("Expanded max height"))

                        Slider(value: $aiAgentExpandedMaxHeightFraction, in: 0.25...0.5, step: 0.05)
                    }
                } header: {
                    Text("灵动岛窗口")
                } footer: {
                    Text("展开 AI 助手标签页时，灵动岛窗口的最大高度占屏幕高度的比例。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("预览")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        AIAgentSessionListView(sessions: previewSessions, style: previewStyle)
                            .frame(maxHeight: 320)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.black.opacity(0.22))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                } header: {
                    Text("预览")
                } footer: {
                    Text("在应用到实际会话前，可在此调整密度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Cleanup
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已结束会话保留时间")
                            Spacer()
                            Text("\(aiAgentExpandedRetentionSeconds) sec")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .settingsHighlight(id: highlightID("Finished session retention"))
                        Slider(
                            value: Binding(
                                get: { Double(aiAgentExpandedRetentionSeconds) },
                                set: { aiAgentExpandedRetentionSeconds = Int($0) }
                            ),
                            in: 5...300,
                            step: 5
                        )

                        HStack {
                            Text("自动清理")
                            Spacer()
                            Text("\(aiAgentAutoCleanupMinutes) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .settingsHighlight(id: highlightID("Auto cleanup"))
                        Slider(
                            value: Binding(
                                get: { Double(aiAgentAutoCleanupMinutes) },
                                set: { aiAgentAutoCleanupMinutes = Int($0) }
                            ),
                            in: 1...60,
                            step: 1
                        )
                    }
                } header: {
                    Text("会话管理")
                } footer: {
                    Text("已结束的任务会立即从折叠的灵动岛中消失，但在展开的 AI 助手标签页中会保留上述时间。自动清理也定义了活动会话在没有新 Hook 事件时可以保持可见多长时间，超时后 Vland 将其视为过期并移除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("AI 助手")
        .onAppear {
            if enableAIAgentFeature {
                agentManager.detectInstalledAgents()
            }
            refreshPreviewSessions()
        }
        .onChange(of: enableAIAgentFeature) { newValue in
            if newValue {
                agentManager.detectInstalledAgents()
            }
        }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "图标导入已取消或失败。"
            }
        }
    }

    // MARK: - Helper functions for agent display

    private func agentIcon(for id: String) -> String {
        switch id {
        case "codebuddy": return "hammer.fill"
        case "claude-code": return "terminal.fill"
        case "cursor": return "cursorarrow.rays"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini-cli": return "sparkles"
        case "workbuddy": return "briefcase.fill"
        default: return "questionmark.circle"
        }
    }

    private func agentColor(for id: String) -> Color {
        switch id {
        case "codebuddy": return .blue
        case "claude-code": return .orange
        case "cursor": return .purple
        case "codex": return .green
        case "gemini-cli": return .cyan
        case "workbuddy": return .indigo
        default: return .gray
        }
    }

    private func agentStatusText(_ agent: AIAgentManager.DetectedAgent) -> String {
        guard agent.configDirExists else { return "未安装" }
        switch agent.hookStatus {
        case .configuredVland:
            return "✓ Hook 已为 Vland 配置"
        case .configuredOther(let name):
            return "⚠ Hook 指向 \(name)（需要更新）"
        case .notConfigured:
            return "Hook 未配置"
        }
    }

    private func agentStatusColor(_ agent: AIAgentManager.DetectedAgent) -> Color {
        guard agent.configDirExists else { return .secondary }
        switch agent.hookStatus {
        case .configuredVland: return .green
        case .configuredOther: return .orange
        case .notConfigured: return .secondary
        }
    }

    private func iconSelectionBinding(for agentType: AIAgentType) -> Binding<String> {
        Binding(
            get: { aiAgentIconSelections[agentType.rawValue] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    aiAgentIconSelections.removeValue(forKey: agentType.rawValue)
                } else {
                    aiAgentIconSelections[agentType.rawValue] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func agentIconPreview(for agentType: AIAgentType) -> some View {
        if let image = AIAgentIconResolver.image(for: agentType) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: agentType.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(agentType.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(agentType.accentColor.opacity(0.12))
                )
        }
    }

    private func iconSelectionDescription(for agentType: AIAgentType) -> String {
        if let selectedID = aiAgentIconSelections[agentType.rawValue],
           let icon = customAppIcons.first(where: { $0.id.uuidString == selectedID }) {
            return "自定义图标：\(icon.name)"
        }

        if AIAgentIconResolver.image(for: agentType) != nil {
            return "使用检测到的应用图标"
        }

        return "使用内置符号"
    }

    // MARK: - Unified Agent Management Card

    @ViewBuilder
    private func agentManagementCard(_ agent: AIAgentManager.DetectedAgent) -> some View {
        let agentType = AIAgentType(rawValue: agent.id) ?? .codebuddy

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Icon + Name + Hook status/configure button
            HStack(spacing: 8) {
                agentIconPreview(for: agentType)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(agentStatusText(agent))
                        .font(.system(size: 10))
                        .foregroundStyle(agentStatusColor(agent))
                }

                Spacer()

                // Configure button or status
                if agent.configDirExists {
                    switch agent.hookStatus {
                    case .configuredVland:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                    case .configuredOther, .notConfigured:
                        Button("配置") {
                            _ = agentManager.configureAgent(agent)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text("未安装")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Row 2: Icon picker
            HStack {
                Text("图标")
                    .font(.system(size: 10))
                    .frame(width: 32, alignment: .leading)

                Picker("", selection: iconSelectionBinding(for: agentType)) {
                    Text("默认").tag("")
                    ForEach(customAppIcons) { icon in
                        Text(icon.name).tag(icon.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Button("导入") {
                    iconImportError = nil
                    isIconImporterPresented = true
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
            }

            // Row 3: Config directory
            HStack {
                Text("目录")
                    .font(.system(size: 10))
                    .frame(width: 32, alignment: .leading)

                TextField("使用默认路径", text: configDirBinding(for: agentType))
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Button {
                    browseConfigDir(for: agentType)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("浏览目录（可选择隐藏目录）")

                if aiAgentCustomConfigDirs[agentType.rawValue] != nil {
                    Button {
                        resetConfigDir(for: agentType)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("重置为默认路径")
                }
            }

            // Directory status
            Text(configDirStatusText(for: agentType))
                .font(.system(size: 9))
                .foregroundStyle(configDirStatusColor(for: agentType))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
    }

    // MARK: - Config Directory Helpers

    private func configDirBinding(for agentType: AIAgentType) -> Binding<String> {
        Binding(
            get: {
                if let custom = self.aiAgentCustomConfigDirs[agentType.rawValue], !custom.isEmpty {
                    return custom
                }
                return self.defaultConfigDir(for: agentType)
            },
            set: { newValue in
                if newValue.isEmpty || newValue == self.defaultConfigDir(for: agentType) {
                    self.aiAgentCustomConfigDirs.removeValue(forKey: agentType.rawValue)
                } else {
                    self.aiAgentCustomConfigDirs[agentType.rawValue] = newValue
                }
                self.agentManager.detectInstalledAgents()
            }
        )
    }

    private func defaultConfigDir(for agentType: AIAgentType) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch agentType {
        case .codebuddy: return (home as NSString).appendingPathComponent(".codebuddy")
        case .claudeCode: return (home as NSString).appendingPathComponent(".claude")
        case .cursor: return (home as NSString).appendingPathComponent(".cursor")
        case .codex: return (home as NSString).appendingPathComponent(".codex")
        case .geminiCLI: return (home as NSString).appendingPathComponent(".gemini")
        case .workbuddy: return (home as NSString).appendingPathComponent(".workbuddy")
        }
    }

    private func browseConfigDir(for agentType: AIAgentType) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = "选择"
        panel.message = "选择 \(agentType.displayName) 的配置目录（通常是以 . 开头的隐藏目录）"

        if panel.runModal() == .OK, let url = panel.url {
            aiAgentCustomConfigDirs[agentType.rawValue] = url.path
            agentManager.detectInstalledAgents()
        }
    }

    private func resetConfigDir(for agentType: AIAgentType) {
        aiAgentCustomConfigDirs.removeValue(forKey: agentType.rawValue)
        agentManager.detectInstalledAgents()
    }

    private func configDirStatusText(for agentType: AIAgentType) -> String {
        let customDir = aiAgentCustomConfigDirs[agentType.rawValue]
        let dirPath: String
        let dirExists: Bool

        if let custom = customDir, !custom.isEmpty {
            dirPath = (custom as NSString).expandingTildeInPath
            dirExists = FileManager.default.fileExists(atPath: dirPath)
            return dirExists ? "✓ 自定义路径有效" : "✗ 路径不存在"
        } else {
            dirPath = defaultConfigDir(for: agentType)
            dirExists = FileManager.default.fileExists(atPath: dirPath)
            return dirExists ? "使用默认路径（已检测到）" : "使用默认路径（未检测到）"
        }
    }

    private func configDirStatusColor(for agentType: AIAgentType) -> Color {
        let customDir = aiAgentCustomConfigDirs[agentType.rawValue]
        let dirPath: String
        let dirExists: Bool

        if let custom = customDir, !custom.isEmpty {
            dirPath = (custom as NSString).expandingTildeInPath
            dirExists = FileManager.default.fileExists(atPath: dirPath)
            return dirExists ? .green : .red
        } else {
            dirPath = defaultConfigDir(for: agentType)
            dirExists = FileManager.default.fileExists(atPath: dirPath)
            return dirExists ? .secondary : .gray
        }
    }

    private func importCustomIcon(from url: URL) {
        guard NSImage(contentsOf: url) != nil else {
            iconImportError = "该文件无法作为图片加载。"
            return
        }

        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "无法保存图标文件。"
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "自定义图标" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        iconImportError = nil
    }

    private func refreshPreviewSessions() {
        previewSessions = Self.makePreviewSessions()
    }

    private static func makePreviewSessions() -> [AIAgentSession] {
        let activeSession = AIAgentSession(agentType: .codex, project: "/Users/zhanwanli/dev/Vland", sessionId: "preview-active")
        activeSession.status = .coding
        activeSession.lastUserPrompt = "Add 8-bit sound effects and a live card preview to the AI agent settings."
        activeSession.currentTask = "Editing AIAgent settings and preview components"
        activeSession.todoItems = [
            AIAgentTodoItem(id: "preview-1", status: .completed, content: "Wire AI agent sound effects"),
            AIAgentTodoItem(id: "preview-2", status: .inProgress, content: "Build live session card preview"),
            AIAgentTodoItem(id: "preview-3", status: .pending, content: "Add per-agent icon customization"),
        ]
        let activeTurn = AIAgentConversationTurn(userPrompt: activeSession.lastUserPrompt ?? "")
        activeTurn.toolCalls = [
            AIAgentToolCall(timestamp: Date(), toolName: "read_file", input: "DynamicIsland/components/Notch/NotchAIAgentView.swift", output: "Loaded", filePath: "DynamicIsland/components/Notch/NotchAIAgentView.swift"),
            AIAgentToolCall(timestamp: Date(), toolName: "replace_in_file", input: "AIAgentSettings.swift", output: nil, filePath: "DynamicIsland/components/Settings/AIAgentSettings.swift"),
        ]
        activeSession.conversationTurns = [activeTurn]

        let waitingSession = AIAgentSession(agentType: .claudeCode, project: "/Users/zhanwanli/dev/Vland", sessionId: "preview-waiting")
        waitingSession.status = .waitingInput
        waitingSession.lastUserPrompt = "Should the preview use the real card component or a lighter mock?"
        waitingSession.currentTask = "Waiting for your input..."
        let waitingTurn = AIAgentConversationTurn(userPrompt: waitingSession.lastUserPrompt ?? "")
        waitingTurn.interactions = [
            AIAgentInteraction(
                timestamp: Date(),
                type: .question,
                title: "Preview Mode",
                message: "Choose how the settings page should render the preview cards.",
                options: ["Use the real card component", "Use a lightweight mock"],
                responseMode: .pasteReply
            )
        ]
        waitingSession.conversationTurns = [waitingTurn]

        return [waitingSession, activeSession]
    }
}

// MARK: - Preset Card View

struct PresetCardView: View {
    let name: String
    let theme: AIAgentCardTheme
    let isSelected: Bool
    let onSelect: () -> Void

    private var resolvedTheme: ResolvedCardTheme {
        ResolvedCardTheme(from: theme)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // Mini card preview
                RoundedRectangle(cornerRadius: resolvedTheme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(resolvedTheme.cardBackgroundOpacity))
                    .frame(width: 60, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: resolvedTheme.cardCornerRadius, style: .continuous)
                            .strokeBorder(Color.blue.opacity(resolvedTheme.cardBorderOpacity), lineWidth: 0.5)
                    )

                Text(name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
