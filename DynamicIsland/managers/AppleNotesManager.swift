/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Foundation
import Combine
import Defaults

/// Represents a note fetched from Apple Notes via AppleScript.
struct AppleNote: Identifiable, Hashable {
    let id: String
    let name: String
    let body: String
    let folderName: String
    let creationDate: Date?
    let modificationDate: Date?
}

/// Manager that syncs with macOS Apple Notes app via AppleScript.
@MainActor
class AppleNotesManager: ObservableObject {
    static let shared = AppleNotesManager()
    
    @Published var notes: [AppleNote] = []
    @Published var folders: [String] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    
    private var refreshTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Fetch Notes
    
    func fetchNotes() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let fetchedNotes = try await fetchNotesFromAppleScript()
                if !Task.isCancelled {
                    self.notes = fetchedNotes
                    self.lastSyncDate = Date()
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isLoading = false
        }
    }
    
    func fetchFolders() {
        Task {
            do {
                let fetchedFolders = try await fetchFoldersFromAppleScript()
                if !Task.isCancelled {
                    self.folders = fetchedFolders
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Create Note
    
    func createNote(title: String, body: String, folderName: String = "Notes") {
        Task {
            do {
                try await createNoteViaAppleScript(title: title, body: body, folderName: folderName)
                fetchNotes()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Delete Note
    
    func deleteNote(noteId: String) {
        Task {
            do {
                let escapedId = noteId.replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "Notes"
                    delete note id "\(escapedId)"
                end tell
                """
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        var error: NSDictionary?
                        let appleScript = NSAppleScript(source: script)
                        appleScript?.executeAndReturnError(&error)
                        if let error = error {
                            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                            continuation.resume(throwing: NSError(domain: "AppleNotesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                        } else {
                            continuation.resume()
                        }
                    }
                }
                // Remove from local cache immediately
                notes.removeAll { $0.id == noteId }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Open Note in Apple Notes
    
    func openInAppleNotes(noteId: String) {
        let script = """
        tell application "Notes"
            activate
            show note id "\(noteId)"
        end tell
        """
        runAppleScript(script)
    }
    
    func openAppleNotes() {
        NSWorkspace.shared.launchApplication("Notes")
    }
    
    // MARK: - AppleScript Helpers
    
    /// Separator used to delimit fields within a single note record.
    private static let fieldSep = "‖‖"
    /// Separator used to delimit note records.
    private static let recordSep = "‡‡"
    
    private func fetchNotesFromAppleScript() async throws -> [AppleNote] {
        let fs = Self.fieldSep
        let rs = Self.recordSep
        // Iterate by folder to avoid errors on notes without a valid container (e.g. recently deleted).
        // Wrap plaintext access in try to handle locked/encrypted notes gracefully.
        let script = """
        set fieldSep to "\(fs)"
        set recSep to "\(rs)"
        set output to ""
        tell application "Notes"
            repeat with f in folders of default account
                set folderName to name of f
                repeat with n in notes of f
                    set noteId to id of n
                    set noteName to name of n
                    try
                        set bodyText to plaintext of n
                        if length of bodyText > 200 then
                            set bodyText to text 1 thru 200 of bodyText
                        end if
                    on error
                        set bodyText to ""
                    end try
                    set output to output & noteId & fieldSep & noteName & fieldSep & bodyText & fieldSep & folderName & recSep
                end repeat
            end repeat
        end tell
        return output
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: NSError(domain: "AppleNotesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }
                
                guard let output = result?.stringValue, !output.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                var notes: [AppleNote] = []
                let records = output.components(separatedBy: rs)
                for record in records {
                    let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let fields = trimmed.components(separatedBy: fs)
                    guard fields.count >= 4 else { continue }
                    
                    let note = AppleNote(
                        id: fields[0],
                        name: fields[1],
                        body: fields[2],
                        folderName: fields[3],
                        creationDate: nil,
                        modificationDate: nil
                    )
                    notes.append(note)
                }
                
                continuation.resume(returning: notes)
            }
        }
    }
    
    private func fetchFoldersFromAppleScript() async throws -> [String] {
        let script = """
        tell application "Notes"
            set folderNames to {}
            repeat with f in folders of default account
                set end of folderNames to name of f
            end repeat
            return folderNames
        end tell
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: NSError(domain: "AppleNotesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }
                
                guard let listResult = result else {
                    continuation.resume(returning: [])
                    return
                }
                
                var folders: [String] = []
                for i in 1...listResult.numberOfItems {
                    if let name = listResult.atIndex(i)?.stringValue {
                        folders.append(name)
                    }
                }
                
                continuation.resume(returning: folders)
            }
        }
    }
    
    private func createNoteViaAppleScript(title: String, body: String, folderName: String) async throws {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Use default folder for reliability across locales
        let script: String
        if folderName.isEmpty || folderName == "Notes" {
            script = """
            tell application "Notes"
                tell default folder of default account
                    make new note with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
                end tell
            end tell
            """
        } else {
            let escapedFolder = folderName.replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            tell application "Notes"
                tell folder "\(escapedFolder)" of default account
                    make new note with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
                end tell
            end tell
            """
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: NSError(domain: "AppleNotesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)
        if let error = error {
            self.errorMessage = error[NSAppleScript.errorMessage] as? String
            return nil
        }
        return result?.stringValue
    }
}
