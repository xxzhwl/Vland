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
import Defaults
import Foundation

enum MenuBarIconStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case defaultIsland
    case robot
    case tvFace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultIsland:
            return "Default"
        case .robot:
            return "Robot"
        case .tvFace:
            return "TV Face"
        }
    }
}

enum MenuBarIconRenderer {
    static func image(for style: MenuBarIconStyle, scale: CGFloat = 1) -> NSImage {
        let canvas = NSSize(width: 18 * scale, height: 18 * scale)
        let image = NSImage(size: canvas)
        image.lockFocus()

        NSColor.labelColor.setFill()

        switch style {
        case .defaultIsland:
            drawDefaultIsland(in: NSRect(origin: .zero, size: canvas))
        case .robot:
            drawRobot(in: NSRect(origin: .zero, size: canvas))
        case .tvFace:
            drawTVFace(in: NSRect(origin: .zero, size: canvas))
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawDefaultIsland(in rect: NSRect) {
        fillPixels(
            [
                "0001111111111000",
                "0011111111111100",
                "0111111111111110",
                "1111111111111111",
                "1111111111111111",
                "1111111111111111",
                "0111111111111110",
                "0011111111111100",
            ],
            in: pixelRect(in: rect, width: 16, height: 8)
        )
    }

    private static func drawRobot(in rect: NSRect) {
        fillPixels(
            [
                "0000000110000000",
                "0000001111000000",
                "0000111111110000",
                "0001111111111000",
                "0011110110111100",
                "0011111111111100",
                "0011011111101100",
                "0011111111111100",
                "0001111111111000",
                "0000100000010000",
            ],
            in: pixelRect(in: rect, width: 16, height: 10)
        )
    }

    private static func drawTVFace(in rect: NSRect) {
        fillPixels(
            [
                "0001100000011000",
                "0000110000110000",
                "0011111111111100",
                "0011111111111100",
                "0011011111101100",
                "0011111111111100",
                "0011100000011100",
                "0011110000111100",
                "0000111111110000",
                "0000010000100000",
            ],
            in: pixelRect(in: rect, width: 16, height: 10)
        )
    }

    private static func pixelRect(in rect: NSRect, width: Int, height: Int) -> NSRect {
        let pixelSize = min(rect.width / CGFloat(width), rect.height / CGFloat(height))
        let pixelWidth = CGFloat(width) * pixelSize
        let pixelHeight = CGFloat(height) * pixelSize
        return NSRect(
            x: rect.midX - pixelWidth / 2,
            y: rect.midY - pixelHeight / 2,
            width: pixelWidth,
            height: pixelHeight
        )
    }

    private static func fillPixels(_ rows: [String], in rect: NSRect) {
        guard let firstRow = rows.first else { return }

        let width = firstRow.count
        let height = rows.count
        let pixelWidth = rect.width / CGFloat(width)
        let pixelHeight = rect.height / CGFloat(height)

        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, value) in row.enumerated() where value == "1" {
                let pixel = NSRect(
                    x: rect.minX + CGFloat(columnIndex) * pixelWidth,
                    y: rect.maxY - CGFloat(rowIndex + 1) * pixelHeight,
                    width: pixelWidth,
                    height: pixelHeight
                )
                NSBezierPath(rect: pixel).fill()
            }
        }
    }
}
