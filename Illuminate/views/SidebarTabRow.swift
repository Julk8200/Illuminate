//
//  SidebarTabRow.swift
//  Illuminate
//

import SwiftUI

struct SidebarTabRow: View {
    @EnvironmentObject private var tabManager: TabManager
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCopyLink: () -> Void
    let onBookmark: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main Tab Row Layer
            HStack(spacing: 10) {
                Capsule()
                    .fill(isActive ? tabManager.windowThemeColor : Color.clear)
                    .frame(width: 4, height: 20)

                favicon(for: tab, isActive: isActive)

                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
                Color.clear.frame(width: 28, height: 28)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.bgElevated : (tab.groupID != nil ? Color.primary.opacity(0.12) : (isHovered ? Color.bgSurface.opacity(0.85) : Color.clear)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                onSelect()
            }
            
            if isHovered || isActive {
                closeButton(for: tab)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
            
            // Loading Bar
            if tab.isLoading && tab.estimatedProgress < 1.0 {
                VStack {
                    Spacer()
                    ProgressView(value: tab.estimatedProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(tabManager.windowThemeColor)
                        .scaleEffect(x: 1, y: 0.5, anchor: .bottom)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            tab.loadAssets()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            isHovered ? tabManager.windowThemeColor.opacity(0.18) : .clear,
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Color.borderGlass : (isHovered ? Color.borderGlass.opacity(0.4) : Color.clear), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(
            color: isHovered ? tabManager.windowThemeColor.opacity(0.25) : .clear,
            radius: isHovered ? 10 : 0,
            y: isHovered ? 4 : 0
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .contextMenu {
            Button("Copy Link") {
                onCopyLink()
            }
            .disabled(tab.url == nil)

            Button("Bookmark Tab") {
                onBookmark()
            }
            .disabled(tab.url == nil)
            
            Divider()
            
            Button("Close Tab", role: .destructive) {
                onClose()
            }
        }
    }

    private func favicon(for tab: Tab, isActive: Bool) -> some View {
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? tabManager.windowThemeColor : Color.textSecondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func closeButton(for tab: Tab) -> some View {
        Button {
            onClose()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 20, height: 20)
                
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
