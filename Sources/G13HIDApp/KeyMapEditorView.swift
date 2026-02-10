import SwiftUI
import AppKit
import G13HID

@available(macOS 13.0, *)
struct KeyMapEditorView: View {
    @ObservedObject var monitor: HIDMonitor
    @State private var selectedGKey: Int? = nil
    @State private var captureMode = false
    @State private var capturedKey = ""
    @State private var keyMappingType: KeyMappingType = .hold
    @State private var showMacroList = false
    @State private var showModifierList = false
    @State private var eventMonitor: Any? = nil
    @Environment(\.dismiss) private var dismiss

    private let rows: [[Int?]] = [
        [1,2,3,4,5,6,7],
        [8,9,10,11,12,13,14],
        [nil,15,16,17,18,19,nil],
        [nil,nil,20,21,22,nil,nil]
    ]

    private enum KeyMappingType: String, CaseIterable {
        case tap = "Tap"
        case hold = "Hold"
    }

    var body: some View {
        ZStack {
            editorSurface
            if let gKey = selectedGKey, let config = monitor.config {
                keyEditOverlay(gKey: gKey, config: config)
            }
        }
    }

    private var editorSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            keyGrid
            Spacer()
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Text("G13 Keymap Editor").font(.title2)
            Spacer()
            Button("Done") { resetTransient(); dismiss() }
        }
        .padding(.bottom, 4)
    }

    private func resetTransient() {
        selectedGKey = nil
        captureMode = false
        showMacroList = false
        showModifierList = false
        capturedKey = ""
        keyMappingType = .hold
    }

    private var keyGrid: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(0..<rows[r].count, id: \.self) { c in
                            if let g = rows[r][c] { keyButton(g) } else { placeholderKey() }
                        }
                    }
                }
                thumbKeysRow
            }
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private func actionLabel(for action: GKeyAction) -> String {
        switch action {
        case .keyTap(let s): return s
        case .keyHold(let s): return "hold: \(s)"
        case .macro(let name): return "macro: \(name)"
        case .disabled: return "(disabled)"
        case .modifier(let kind): return "mod: \(kind.displayName)"
        }
    }

    private func keyButton(_ g: Int) -> some View {
        let display = monitor.config?.gKeys.first(where: { $0.keyNumber == g }).map { actionLabel(for: $0.action) } ?? "—"
        return Button { selectedGKey = g } label: {
            VStack(spacing: 4) {
                Text("G\(g)").font(.caption).bold()
                Text(display)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 70)
            }
            .padding(6)
            .frame(width: 80, height: 60)
            .background(selectedGKey == g ? Color.blue.opacity(0.25) : Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func placeholderKey() -> some View { Rectangle().foregroundColor(.clear).frame(width: 80, height: 60) }

    private var thumbKeysRow: some View {
        HStack(spacing: 8) {
            Spacer()
            thumbKeyLabel("Thumb1")
            thumbKeyLabel("Thumb2")
        }
        .padding(.top, 12)
    }

    private func thumbKeyLabel(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).bold()
            Text("(joy)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(6)
        .frame(width: 80, height: 60)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private func keyEditOverlay(gKey: Int, config: G13Config) -> some View {
        VStack(spacing: 12) {
            Text("Edit G\(gKey)").font(.headline)
            Group {
                if captureMode { captureSection(gKey: gKey) }
                else if showMacroList { macroListSection(gKey: gKey, config: config) }
                else if showModifierList { modifierListSection(gKey: gKey) }
                else { chooserSection(gKey: gKey, config: config) }
            }
        }
        .padding(20)
        .frame(width: 360, height: 400)
        .background(.thinMaterial)
        .cornerRadius(16)
        .shadow(radius: 18)
        .overlay(alignment: .topTrailing) { Button { selectedGKey = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain).padding(8) }
        .onAppear { startCaptureListenerIfNeeded() }
        .onDisappear { stopCaptureListener() }
        .onChange(of: captureMode) { _ in captureMode ? startCaptureListenerIfNeeded() : stopCaptureListener() }
    }

    private func captureSection(gKey: Int) -> some View {
        VStack(spacing: 8) {
            Text("Press a key on your physical keyboard…").foregroundColor(.secondary)
            Picker("Mapping Type", selection: $keyMappingType) {
                ForEach(KeyMappingType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            Text(capturedKey.isEmpty ? "(waiting)" : capturedKey).font(.title3)
            HStack {
                Button("Use \(capturedKey.isEmpty ? "(none)" : capturedKey)") {
                    if !capturedKey.isEmpty {
                        let mappedKey = capturedKey.lowercased()
                        let action: GKeyAction = keyMappingType == .hold ? .keyHold(mappedKey) : .keyTap(mappedKey)
                        monitor.updateMapping(for: gKey, action: action)
                    }
                    captureMode = false; capturedKey = ""; selectedGKey = nil
                }.disabled(capturedKey.isEmpty)
                Button("Cancel") { captureMode = false }
            }
        }
    }

    private func macroListSection(gKey: Int, config: G13Config) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Macro").font(.subheadline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(config.macros.keys.sorted()), id: \.self) { key in
                        Button {
                            monitor.updateMapping(for: gKey, action: .macro(key))
                            showMacroList = false; selectedGKey = nil
                        } label: {
                            VStack(alignment: .leading) {
                                Text(key).bold()
                                Text(config.macros[key]?.name ?? "").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                }.padding(4)
            }
            Button("Cancel") { showMacroList = false }
        }
    }

    private func modifierListSection(gKey: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Modifier").font(.subheadline)
            ForEach(ModifierKind.allCases, id: \.self) { kind in
                Button(kind.displayName) {
                    monitor.updateMapping(for: gKey, action: .modifier(kind))
                    showModifierList = false; selectedGKey = nil
                }.buttonStyle(.bordered)
            }
            Button("Cancel") { showModifierList = false }
        }
    }

    private func chooserSection(gKey: Int, config: G13Config) -> some View {
        VStack(spacing: 10) {
            let currentAction = config.gKeys.first(where: { $0.keyNumber == gKey })?.action
            if let current = currentAction {
                Text("Current: \(actionLabel(for: current))").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Button("Map Key") {
                    keyMappingType = mappingType(from: currentAction)
                    captureMode = true
                    capturedKey = ""
                }
                Button("Map Macro") { showMacroList = true }
                Button("Map Modifier") { showModifierList = true }
                Button("Disable") {
                    monitor.updateMapping(for: gKey, action: .disabled)
                    selectedGKey = nil
                }
            }
            Button("Close") { selectedGKey = nil }.padding(.top, 4)
        }
    }

    // MARK: Key capture
    private func startCaptureListenerIfNeeded() {
        guard captureMode else { return }
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                if captureMode { capturedKey = normalizeKey(event); return nil }
                return event
            }
        }
    }
    private func stopCaptureListener() { if let m = eventMonitor { NSEvent.removeMonitor(m) }; eventMonitor = nil }

    private func normalizeKey(_ event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return specialKeyName(from: event.keyCode) ?? chars.lowercased()
        }
        return specialKeyName(from: event.keyCode) ?? "unknown"
    }

    private func mappingType(from action: GKeyAction?) -> KeyMappingType {
        switch action {
        case .keyTap: return .tap
        case .keyHold: return .hold
        default: return .hold
        }
    }

    private func specialKeyName(from keyCode: UInt16) -> String? {
        let mapping: [UInt16: String] = [
            53: "escape", 48: "tab", 122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            49: "space", 36: "return", 51: "delete", 117: "forwarddelete", 123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup", 121: "pagedown"
        ]
        return mapping[keyCode]
    }
}

@available(macOS 13.0, *)
struct KeyMapEditorView_Previews: PreviewProvider { static var previews: some View { KeyMapEditorView(monitor: HIDMonitor()) } }
