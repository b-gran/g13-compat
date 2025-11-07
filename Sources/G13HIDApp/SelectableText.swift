import SwiftUI
import AppKit

struct SelectableText: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.refusesFirstResponder = false
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }
} 