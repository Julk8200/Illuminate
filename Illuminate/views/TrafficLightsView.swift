//
//  TrafficLightsView.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

import SwiftUI
import AppKit

struct TrafficLightsView: View {
    @EnvironmentObject private var tabManager: TabManager
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            
            TrafficLightCircle(color: .red, symbol: "xmark") {
                NSApp.keyWindow?.close()
            }
            
            TrafficLightCircle(
                color: .yellow,
                symbol: "minus",
                isGreyedOut: tabManager.isFullScreen
            ) {
                if !tabManager.isFullScreen {
                    NSApp.keyWindow?.miniaturize(nil)
                }
            }
            
            TrafficLightCircle(color: .green, symbol: "plus") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
        .onHover { hovering in
            isHovered = hovering
        }
        .environment(\.isTrafficLightHovered, isHovered)
    }
}

private struct TrafficLightCircle: View {
    let color: TrafficLightColor
    let symbol: String
    var isGreyedOut: Bool = false
    let action: () -> Void
    
    @Environment(\.isTrafficLightHovered) var isHovered
    
    var body: some View {
        Button(action: action) {
            ZStack {
                
                Circle()
                    .fill(circleGradient)
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 0.5)
                    )
                
                if isHovered && !isGreyedOut {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isGreyedOut)
    }
    
    private var circleGradient: LinearGradient {
        LinearGradient(
            colors: isGreyedOut
                ? [Color.gray.opacity(0.25), Color.gray.opacity(0.35)]
                : color.gradient,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var borderColor: Color {
        isGreyedOut ? Color.black.opacity(0.08) : color.border
    }
}

enum TrafficLightColor {
    case red
    case yellow
    case green
    
    var gradient: [Color] {
        switch self {
        case .red:
            return [
                Color(red: 1.0, green: 0.37, blue: 0.34),
                Color(red: 0.86, green: 0.17, blue: 0.14)
            ]
            
        case .yellow:
            return [
                Color(red: 1.0, green: 0.79, blue: 0.32),
                Color(red: 0.93, green: 0.61, blue: 0.06)
            ]
            
        case .green:
            return [
                Color(red: 0.39, green: 0.86, blue: 0.39),
                Color(red: 0.16, green: 0.68, blue: 0.21)
            ]
        }
    }
    
    var border: Color {
        switch self {
        case .red:
            return Color(red: 0.65, green: 0.1, blue: 0.1).opacity(0.4)
        case .yellow:
            return Color(red: 0.65, green: 0.45, blue: 0.05).opacity(0.4)
        case .green:
            return Color(red: 0.05, green: 0.45, blue: 0.1).opacity(0.4)
        }
    }
}

private struct TrafficLightHoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isTrafficLightHovered: Bool {
        get { self[TrafficLightHoverKey.self] }
        set { self[TrafficLightHoverKey.self] = newValue }
    }
}