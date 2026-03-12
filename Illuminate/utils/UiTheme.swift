//
//  UiTheme.swift
//  Illuminate
//
//  Created by MrBlankCoding
//

import SwiftUI
import AppKit

// Grabbed this straight from the web
// UI IN SWIFT SUCKS!

extension Color {

    // Base surfaces
    static let bgBase = Color(nsColor: .windowBackgroundColor)
    static let bgSurface = Color.primary.opacity(0.05)
    static let bgElevated = Color.primary.opacity(0.08)

    // Text hierarchy
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    // Accent
    static let accentBeam = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.25)

    // Borders
    static let borderGlass = Color.primary.opacity(0.14)

    // Panels
    static let sidebarPanel = Color.primary.opacity(0.035)
}


extension Color {

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64

        switch hex.count {
        case 3:
            (a, r, g, b) = (255,
                            (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)

        case 6:
            (a, r, g, b) = (255,
                            int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)

        case 8:
            (a, r, g, b) = (int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8 & 0xFF,
                            int & 0xFF)

        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)

        guard let components = nsColor.cgColor.components else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = components.count >= 4 ? Float(components[3]) : 1.0

        if a < 1 {
            return String(
                format: "%02lX%02lX%02lX%02lX",
                lroundf(r * 255),
                lroundf(g * 255),
                lroundf(b * 255),
                lroundf(a * 255)
            )
        }

        return String(
            format: "%02lX%02lX%02lX",
            lroundf(r * 255),
            lroundf(g * 255),
            lroundf(b * 255)
        )
    }
}

struct GlassModifier: ViewModifier {

    var cornerRadius: CGFloat = 12
    var material: Material = .regularMaterial

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(material)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.borderGlass, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.08),
                radius: 10,
                y: 4
            )
    }
}

extension Font {

    static let webH1 = Font.system(size: 28, weight: .semibold)
    static let webH2 = Font.system(size: 22, weight: .medium)
    static let webBody = Font.system(size: 15)
    static let webMicro = Font.system(size: 12)
}

struct GlassButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .font(.webBody)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.thinMaterial)
            )

            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.borderGlass)
            )

            .scaleEffect(configuration.isPressed ? 0.96 : 1)

            .animation(
                .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

struct FocusRingModifier: ViewModifier {

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.accentBeam : Color.clear,
                        lineWidth: 2
                    )
            )
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

struct CavedDivider: View {

    var body: some View {

        Rectangle()
            .fill(Color.borderGlass)
            .frame(height: 1)
            .opacity(0.6)
            .padding(.vertical, 4)
    }
}

extension View {

    func glassBackground() -> some View {
        self.modifier(GlassModifier())
    }

    func focusRing(_ active: Bool) -> some View {
        self.modifier(FocusRingModifier(isActive: active))
    }

    func hoverCursor(_ cursor: NSCursor) -> some View {
        self.modifier(HoverCursorModifier(cursor: cursor))
    }
}
private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

