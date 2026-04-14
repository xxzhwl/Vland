//
//  ScreenAssistantSettings.swift
//  DynamicIsland
//
//  Split from SettingsView.swift
//
import KeyboardShortcuts
import SwiftUI
import Defaults

struct ScreenAssistantSettings: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @StateObject private var screenRecordingTool = ScreenRecordingTool.shared
    @Default(.enableScreenAssistant) var enableScreenAssistant
    @Default(.screenAssistantDisplayMode) var screenAssistantDisplayMode
    @Default(.enableScreenAssistantScreenshot) var enableScreenAssistantScreenshot
    @Default(.enableScreenAssistantScreenRecording) var enableScreenAssistantScreenRecording
    @Default(.autoSaveScreenAssistantScreenshots) var autoSaveScreenAssistantScreenshots
    @Default(.screenAssistantScreenshotSavePath) var screenAssistantScreenshotSavePath
    @Default(.screenAssistantRecordingSavePath) var screenAssistantRecordingSavePath
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.geminiApiKey) var geminiApiKey
    @State private var apiKeyText = ""
    @State private var showingApiKey = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.screenAssistant.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenAssistant) {
                    Text("Enable Screen Assistant")
                }
                .settingsHighlight(id: highlightID("Enable Screen Assistant"))
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("AI-powered assistant that can analyze files, images, and provide conversational help. Use Cmd+Shift+A to quickly access the assistant.")
            }

            if enableScreenAssistant {
                Section {
                    HStack {
                        Text("Gemini API Key")
                        Spacer()
                        if geminiApiKey.isEmpty {
                            Text("Not Set")
                                .foregroundColor(.red)
                        } else {
                            Text("••••••••")
                                .foregroundColor(.green)
                        }

                        Button(showingApiKey ? "Hide" : (geminiApiKey.isEmpty ? "Set" : "Change")) {
                            if showingApiKey {
                                showingApiKey = false
                                if !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Defaults[.geminiApiKey] = apiKeyText
                                }
                                apiKeyText = ""
                            } else {
                                showingApiKey = true
                                apiKeyText = geminiApiKey
                            }
                        }
                    }

                    if showingApiKey {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Enter your Gemini API Key", text: $apiKeyText)
                                .textFieldStyle(.roundedBorder)

                            Text("Get your free API key from Google AI Studio")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Button("Open Google AI Studio") {
                                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                                }
                                .buttonStyle(.link)

                                Spacer()

                                Button("Save") {
                                    Defaults[.geminiApiKey] = apiKeyText
                                    showingApiKey = false
                                    apiKeyText = ""
                                }
                                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    HStack {
                        Text("Display Mode")
                        Spacer()
                        Picker("", selection: $screenAssistantDisplayMode) {
                            ForEach(ScreenAssistantDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    HStack {
                        Text("Attached Files")
                        Spacer()
                        Text("\(screenAssistantManager.attachedFiles.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Recording Status")
                        Spacer()
                        Text(screenAssistantManager.isRecording ? "Recording" : "Ready")
                            .foregroundColor(screenAssistantManager.isRecording ? .red : .secondary)
                    }
                    
                    HStack {
                        Text("Screen Recording Status")
                        Spacer()
                        Text(screenRecordingTool.isRecording ? "Recording" : "Ready")
                            .foregroundColor(screenRecordingTool.isRecording ? .red : .secondary)
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    switch screenAssistantDisplayMode {
                    case .popover:
                        Text("Popover mode shows the assistant as a dropdown attached to the AI button. Panel mode shows the assistant in a floating window near the notch.")
                    case .panel:
                        Text("Panel mode shows the assistant in a floating window near the notch. Popover mode shows the assistant as a dropdown attached to the AI button.")
                    }
                }
                
                Section {
                    Defaults.Toggle(key: .enableScreenAssistantScreenshot) {
                        Text("Enable Screenshot")
                    }
                    Defaults.Toggle(key: .enableScreenAssistantScreenRecording) {
                        Text("Enable Screen Recording")
                    }
                    Defaults.Toggle(key: .autoSaveScreenAssistantScreenshots) {
                        Text("Auto Save Screenshots")
                    }
                    .disabled(!enableScreenAssistantScreenshot)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Post-capture workflow")
                            .font(.subheadline)
                        Text("After taking a screenshot, use the floating studio to mark, mosaic, add text, save to a folder, send to chat, or pin it to the screen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Screenshot Save Folder")
                            Spacer()
                            Button("Choose…", action: chooseScreenshotDirectory)
                                .disabled(!enableScreenAssistantScreenshot)
                            Button("Default") {
                                screenAssistantScreenshotSavePath = ""
                            }
                            .disabled(!enableScreenAssistantScreenshot)
                        }
                        Text(displayPath(for: screenAssistantScreenshotSavePath, fallback: ScreenAssistantManager.screenshotDataDirectory.path))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Recording Save Folder")
                            Spacer()
                            Button("Choose…", action: chooseRecordingDirectory)
                                .disabled(!enableScreenAssistantScreenRecording)
                            Button("Default") {
                                screenAssistantRecordingSavePath = ""
                            }
                            .disabled(!enableScreenAssistantScreenRecording)
                        }
                        Text(displayPath(for: screenAssistantRecordingSavePath, fallback: ScreenAssistantManager.screenRecordingDataDirectory.path))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Capture & Recording")
                } footer: {
                    Text("When auto-save is off, screenshots are kept in a temporary cache for assistant attachments instead of your configured save folder.")
                }
                
                Section {
                    KeyboardShortcuts.Recorder("Screenshot:", name: .screenAssistantScreenshot)
                        .disabled(!enableShortcuts || !enableScreenAssistantScreenshot)
                    
                    KeyboardShortcuts.Recorder("Screen Recording:", name: .screenAssistantScreenRecording)
                        .disabled(!enableShortcuts || !enableScreenAssistantScreenRecording)
                } header: {
                    Text("Capture Shortcuts")
                } footer: {
                    Text("These are the same shortcuts shown in the global `Shortcuts` page, added here for easier discovery.")
                }

                Section {
                    Button("Clear All Files") {
                        screenAssistantManager.clearAllFiles()
                    }
                    .foregroundColor(.red)
                    .disabled(screenAssistantManager.attachedFiles.isEmpty)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Clear all files removes all attached files and audio recordings. This action is permanent.")
                }

                if !screenAssistantManager.attachedFiles.isEmpty {
                    Section {
                        ForEach(screenAssistantManager.attachedFiles) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: file.type.iconName)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(file.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(timeAgoString(from: file.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(file.name)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Attached Files")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screen Assistant")
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func chooseScreenshotDirectory() {
        if let path = chooseDirectory(title: "Select Screenshot Save Folder") {
            screenAssistantScreenshotSavePath = path
        }
    }
    
    private func chooseRecordingDirectory() {
        if let path = chooseDirectory(title: "Select Recording Save Folder") {
            screenAssistantRecordingSavePath = path
        }
    }
    
    private func chooseDirectory(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    
    private func displayPath(for configuredPath: String, fallback: String) -> String {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
