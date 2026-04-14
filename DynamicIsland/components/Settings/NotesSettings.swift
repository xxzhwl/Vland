//
//  NotesSettings.swift
//  DynamicIsland
//
//  Split from SettingsView.swift
//
import SwiftUI
import Defaults

struct NotesSettingsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.notes.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotes) {
                    Text("Enable Notes")
                }
                if Defaults[.enableNotes] {
                    Defaults.Toggle(key: .syncAppleNotes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync with Apple Notes")
                            Text("Display and create notes from macOS Notes app instead of built-in storage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if !Defaults[.syncAppleNotes] {
                        Defaults.Toggle(key: .enableNotePinning) {
                            Text("Enable Note Pinning")
                        }
                        Defaults.Toggle(key: .enableNoteSearch) {
                            Text("Enable Note Search")
                        }
                        Defaults.Toggle(key: .enableNoteColorFiltering) {
                            Text("Enable Color Filtering")
                        }
                        Defaults.Toggle(key: .enableCreateFromClipboard) {
                            Text("Enable Create from Clipboard")
                        }
                        Defaults.Toggle(key: .enableNoteCharCount) {
                            Text("Show Character Count")
                        }
                    }
                }
            } header: {
                Text("General")
            } footer: {
                if Defaults[.syncAppleNotes] {
                    Text("Notes are synced from the macOS Notes app. Tap a note to select, tap again to open in Notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Customize how you organize and create notes. Enabling color filtering and search helps manage large lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Notes")
    }
}

// MARK: - Terminal Settings

