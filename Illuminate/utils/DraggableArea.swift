//
//  DraggableArea.swift
//  Illuminate
//
//  Created by MrBlankCoding CLI on 3/18/26.
//

import SwiftUI
import AppKit

struct DraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class DragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
