import SwiftUI

/// A pixel-art style crab icon used for Claude Code.
struct PixelCrabIcon: View {
    var tint: Color = .orange
    var size: CGSize = CGSize(width: 14, height: 14)

    /// 14-wide × 11-tall pixel grid forming a crab silhouette.
    /// `true` = filled pixel, `false` = transparent.
    private static let pixelGrid: [[Bool]] = [
        [false, false, false, true,  true,  false, false, false, false, true,  true,  false, false, false],
        [false, false, true,  true,  true,  true,  false, false, true,  true,  true,  true,  false, false],
        [false, true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  false, false, true,  true,  true,  true,  true,  true,  false, false, true,  true],
        [true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true],
        [false, true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  true,  false],
        [false, false, true,  true,  true,  true,  false, false, true,  true,  true,  true,  false, false],
        [false, false, true,  true,  true,  false, false, false, false, true,  true,  true,  false, false],
        [false, false, false, true,  true,  false, false, false, false, true,  true,  false, false, false],
    ]

    private var columns: Int { Self.pixelGrid.first?.count ?? 14 }
    private var rows: Int { Self.pixelGrid.count }

    var body: some View {
        Canvas { context, _ in
            let cellW = size.width / CGFloat(columns)
            let cellH = size.height / CGFloat(rows)
            let pixelSize = min(cellW, cellH)

            for row in 0..<rows {
                for col in 0..<columns where Self.pixelGrid[row][col] {
                    let rect = CGRect(
                        x: CGFloat(col) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    ).insetBy(dx: pixelSize * 0.08, dy: pixelSize * 0.08)
                    context.fill(Path(roundedRect: rect, cornerRadius: pixelSize * 0.18), with: .color(tint))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A reusable agent type icon that handles Claude Code (pixel crab), custom icons, and SF Symbols.
struct AgentTypeIconView: View {
    let agentType: AIAgentType
    let size: CGFloat

    private var pixelSize: CGSize {
        CGSize(width: size, height: size)
    }

    var body: some View {
        Group {
            if let image = AIAgentIconResolver.image(for: agentType) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            } else if agentType == .claudeCode {
                PixelCrabIcon(tint: agentType.accentColor, size: pixelSize)
            } else {
                Image(systemName: agentType.iconName)
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundColor(agentType.accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}
