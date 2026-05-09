import SwiftUI

// MARK: - Icon Gallery

struct AIAgentIconGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeaderTitle("Agent Type Icons")
                iconGrid
            }
            .padding(24)
        }
        .frame(width: 520, height: 200)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var iconGrid: some View {
        HStack(spacing: 16) {
            ForEach(AIAgentType.allCases) { type in
                VStack(spacing: 8) {
                    AgentTypeIconView(agentType: type, size: 28)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(type.accentColor.opacity(0.1))
                        )
                    Text(type.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }
        }
    }
}

// MARK: - Chat Preview Gallery

struct AIAgentChatGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeaderTitle("Chat: Claude Code (Pixel Crab)")
                claudeChatPreview

                Divider().padding(.vertical, 4)

                HeaderTitle("Chat: Cursor")
                cursorChatPreview
            }
            .padding(24)
        }
        .frame(width: 520, height: 600)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    // Claude Code chat — pixel crab icon
    private var claudeChatPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClaudeAIBubble()
            UserBubble(text: "Can you make the Claude icon look like a pixel crab instead of the terminal symbol? Something retro and fun!")
            ClaudeResponseBubble()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    private var cursorChatPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            CursorAIBubble()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }
}

// MARK: - Bubble Sub-views

private struct ClaudeAIBubble: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            iconFrame(agentType: .claudeCode, color: .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.9))
                innerBubble(accent: .orange, content: aiMessageContent)
            }
            .padding(.trailing, 20)
        }
    }
}

private struct CursorAIBubble: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            iconFrame(agentType: .cursor, color: .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cursor")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple.opacity(0.9))
                innerBubble(accent: .purple, content: cursorMessageContent)
            }
            .padding(.trailing, 20)
        }
    }
}

private struct UserBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Text("14:30:22")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                Text(text)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.06)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            }
        }
    }
}

private struct ClaudeResponseBubble: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            AgentTypeIconView(agentType: .claudeCode, size: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Code")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.9))

                toolCallRow

                Text("Sure! I'll create a pixel-art crab icon using a 14×11 grid of rounded rects. Here's the design I'm thinking of — a crab with eyes, claws, and legs rendered in pixel style.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.orange.opacity(0.06), .orange.opacity(0.03)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.08), lineWidth: 0.5))
        }
    }
}

// MARK: - Shared Helper Views

private func iconFrame(agentType: AIAgentType, color: Color) -> some View {
    AgentTypeIconView(agentType: agentType, size: 18)
        .frame(width: 20, height: 20)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
}

private func innerBubble(accent: Color, content: Text) -> some View {
    content
        .lineSpacing(2)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.08), accent.opacity(0.03)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.12), lineWidth: 0.5))
}

private var aiMessageContent: Text {
    Text("I've updated the `PixelCrabIcon` view with a new pixel-art crab design. The icon now renders as a **14×11 pixel grid** using Core Graphics for crisp rendering at any size.")
}

private var cursorMessageContent: Text {
    Text("Found the issue — there was a type mismatch in the JSON decoder. Fixed it by adding a custom `init(from:)` that handles both snake_case and camelCase keys.")
}

private var toolCallRow: some View {
    HStack(spacing: 6) {
        Image(systemName: "wrench.and.screwdriver.fill")
            .font(.system(size: 7)).foregroundColor(.cyan.opacity(0.7))
        Text("write_to_file")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.cyan.opacity(0.85))
    }
    .padding(.horizontal, 6).padding(.vertical, 3)
    .background(RoundedRectangle(cornerRadius: 4).fill(Color.cyan.opacity(0.06)))
}

private struct HeaderTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}

// MARK: - Session Card Gallery

struct AIAgentSessionCardGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(AIAgentType.allCases) { type in
                    sessionCard(for: type)
                }
            }
            .padding(12)
        }
        .frame(width: 500, height: 400)
        .background(Color.black.opacity(0.95))
        .preferredColorScheme(.dark)
    }

    private func sessionCard(for type: AIAgentType) -> some View {
        HStack(spacing: 8) {
            pulsingDot(color: type == .claudeCode ? .yellow : .green)
            AgentTypeIconView(agentType: type, size: 14)
            Text(type.displayName)
                .font(.system(size: 12, weight: .bold)).foregroundColor(type.accentColor)
            Text("｜").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
            Text("Refactored the auth flow to use OAuth2 PKCE")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
            Spacer()
            Text("/Users/workspace").font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(type.accentColor.opacity(0.15), lineWidth: 0.5))
    }

    private func pulsingDot(color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7).padding(3)
            .background(Circle().fill(color.opacity(0.3)))
            .frame(width: 12, height: 12)
    }
}

#Preview("Icons") {
    AIAgentIconGallery()
}

#Preview("Chat") {
    AIAgentChatGallery()
}

#Preview("Cards") {
    AIAgentSessionCardGallery()
}
