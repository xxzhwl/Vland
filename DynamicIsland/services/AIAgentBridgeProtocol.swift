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

import Foundation

// MARK: - AI Agent Bridge Protocol

/// Handles bridge response protocol adaptation for different AI agent types.
/// This is a pure logic service with no side effects - suitable for unit testing.
enum AIAgentBridgeProtocol {
    /// Generates the JSON payload to send back to the bridge for a given interaction and user response.
    static func responsePayload(
        for interaction: AIAgentInteraction,
        option: String
    ) -> [String: Any]? {
        if let payload = bridgeSpecificResponsePayload(for: interaction, option: option) {
            return payload
        }

        switch interaction.responseMode {
        case .approvalSelection:
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return ["decision": "allow"]
            }

            return [
                "decision": "block",
                "reason": "User rejected from Vland",
            ]

        case .pasteReply:
            return [
                "decision": "allow",
                "selected": [option],
            ]
        }
    }

    /// Agent-specific response payloads for specialized bridge protocols.
    private static func bridgeSpecificResponsePayload(
        for interaction: AIAgentInteraction,
        option: String
    ) -> [String: Any]? {
        guard let kind = interaction.bridgeResponseKind else { return nil }

        switch kind {
        case "claude_permission_request":
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "allow"
                        ]
                    ]
                ]
            }

            return [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "deny",
                        "message": "User rejected from Vland",
                        "interrupt": false
                    ]
                ]
            ]

        case "claude_ask_user_question":
            guard let context = bridgeResponseContext(from: interaction.bridgeResponseContext),
                  var toolInput = context["tool_input"] as? [String: Any],
                  let question = context["question"] as? String else {
                return nil
            }

            var answers = toolInput["answers"] as? [String: String] ?? [:]
            answers[question] = option
            toolInput["answers"] = answers

            return [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "updatedInput": toolInput
                ]
            ]

        case "codebuddy_ask_user_question":
            guard let context = bridgeResponseContext(from: interaction.bridgeResponseContext),
                  var toolInput = context["tool_input"] as? [String: Any],
                  let question = context["question"] as? String else {
                return nil
            }

            var answers = toolInput["answers"] as? [String: String] ?? [:]
            answers[question] = option
            toolInput["answers"] = answers

            return [
                "hookSpecificOutput": [
                    "permissionDecision": "allow",
                    "modifiedInput": toolInput
                ]
            ]

        case "codebuddy_approval":
            // Use CodeBuddy native hookSpecificOutput protocol
            if option.caseInsensitiveCompare("Allow") == .orderedSame
                || option.caseInsensitiveCompare("Yes") == .orderedSame {
                return [
                    "hookSpecificOutput": [
                        "permissionDecision": "allow"
                    ]
                ]
            }
            return [
                "hookSpecificOutput": [
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "User rejected from Vland"
                ]
            ]

        default:
            return nil
        }
    }

    private static func bridgeResponseContext(from rawValue: String?) -> [String: Any]? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}