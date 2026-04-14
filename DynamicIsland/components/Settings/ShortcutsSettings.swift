//
//  ShortcutsSettings.swift
//  DynamicIsland
//
//  Split from SettingsView.swift
//
import SwiftUI
import Defaults
import KeyboardShortcuts

struct Shortcuts: View {
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.enableScreenAssistantScreenshot) var enableScreenAssistantScreenshot
    @Default(.enableScreenAssistantScreenRecording) var enableScreenAssistantScreenRecording
    @Default(.enablePluginLauncher) var enablePluginLauncher

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Text("Enable global keyboard shortcuts")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableShortcuts {
                Section {
                    KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Media")
                } footer: {
                    Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Toggle the Dynamic Island open or closed from anywhere.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Start Demo Timer:", name: .startDemoTimer)
                                .disabled(!enableShortcuts || !enableTimerFeature)
                            if !enableTimerFeature {
                                Text("Timer feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    Text("Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Clipboard History:", name: .clipboardHistoryPanel)
                                .disabled(!enableShortcuts || !enableClipboardManager)
                            if !enableClipboardManager {
                                Text("Clipboard feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Clipboard")
                } footer: {
                    Text("Opens the clipboard history panel. Default is Cmd+Shift+V (similar to Windows+V on PC). Only works when clipboard feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Screen Assistant:", name: .screenAssistantPanel)
                                .disabled(!enableShortcuts || !Defaults[.enableScreenAssistant])
                            if !Defaults[.enableScreenAssistant] {
                                Text("Screen Assistant feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("Opens the AI assistant panel for file analysis and conversation. Default is Cmd+Shift+A. Only works when screen assistant feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            KeyboardShortcuts.Recorder("Take Screenshot:", name: .screenAssistantScreenshot)
                                .disabled(!enableShortcuts || !Defaults[.enableScreenAssistant] || !enableScreenAssistantScreenshot)
                            KeyboardShortcuts.Recorder("Toggle Screen Recording:", name: .screenAssistantScreenRecording)
                                .disabled(!enableShortcuts || !Defaults[.enableScreenAssistant] || !enableScreenAssistantScreenRecording)
                            
                            if !Defaults[.enableScreenAssistant] {
                                Text("Screen Assistant feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            } else if !enableScreenAssistantScreenshot || !enableScreenAssistantScreenRecording {
                                Text("Enable screenshot and recording in Screen Assistant settings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Screen Capture")
                } footer: {
                    Text("Global shortcuts for screenshot and screen recording in the AI assistant workflow.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Toggle Terminal Tab:", name: .toggleTerminalTab)
                                .disabled(!enableShortcuts || !Defaults[.enableTerminalFeature])
                            if !Defaults[.enableTerminalFeature] {
                                Text("Terminal feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Opens the terminal tab in the notch. Default is Ctrl+`. Only works when terminal feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Quick Launch:", name: .openPluginLauncher)
                                .disabled(!enableShortcuts || !enablePluginLauncher)
                        if !enablePluginLauncher {
                            Text("Quick Launch feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Quick Launch")
                } footer: {
                    Text("Opens Quick Launch to quickly search and use tools. Default is Cmd+Shift+Space. Supports clipboard search and extensible imported plugins.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Color Picker Panel:", name: .colorPickerPanel)
                                .disabled(!enableShortcuts || !enableColorPickerFeature)
                            if !enableColorPickerFeature {
                                Text("Color Picker feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Color Picker")
                } footer: {
                    Text("Opens the color picker panel for screen color capture. Default is Cmd+Shift+P. Only works when color picker feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts are disabled")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Shortcuts")
    }
}
