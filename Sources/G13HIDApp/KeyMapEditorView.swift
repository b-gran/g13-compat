import SwiftUI
import AppKit
import G13HID

/// Visual editor representing the physical G13 key layout and allowing mapping edits.
@available(macOS 13.0, *)
struct KeyMapEditorView: View {
    @ObservedObject var monitor: HIDMonitor
    @State private var selectedGKey: Int? = nil
    @State private var captureMode: Bool = false
    @State private var capturedKey: String = ""
    @State private var showMacroList: Bool = false
    @State private var eventMonitor: Any? = nil // NSEvent local monitor
    @Environment(\.dismiss) private var dismiss // sheet dismissal

    // Ortholinear 7-column layout centered on middle (column index 3, zero-based).
    // Shorter rows are padded with nil placeholders to center keys.
    // Row counts: 7,7,5,3
    // Two additional thumb keys (non-mappable currently) shown beside joystick area.
    //
    // Representation details:
    // - The physical G13 presents 22 programmable G keys in a vertical stagger physically, but
    //   functionally they align to an ortholinear grid for editing purposes; we render 7 columns.
    // - We keep G key numbering contiguous (G1..G22) and insert nil placeholders ONLY for visual centering.
    //   Nil entries render as transparent 80x60 rectangles matching the button footprint so alignment holds.
    // - Rows with fewer keys (5 and 3) are symmetrically padded to keep their active keys centered on column 3.
    // - Thumb keys are displayed for spatial orientation; they are not yet editable because current config
    //   schema lacks explicit thumb key actions (could be extended later as joystick or modifier inputs).
    // - If future support adds thumb mapping, convert thumbKeysRow into the same keyButton() rendering path
    //   with distinct identifiers (e.g., negative indices or a separate enum) while preserving JSON backward compatibility.
    private let rows: [[Int?]] = [
        [1,2,3,4,5,6,7],                // 7 keys
        [8,9,10,11,12,13,14],           // 7 keys
        [nil,15,16,17,18,19,nil],       // centered 5 keys
        [nil,nil,20,21,22,nil,nil]      // centered 3 keys
    ]

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
            Text("G13 Keymap Editor")
                .font(.title2)
            Spacer()
            Button("Done") {
                // Clear transient state then dismiss hosting sheet
                selectedGKey = nil
                captureMode = false
                showMacroList = false
                capturedKey = ""
                dismiss()
            }
        }
        .padding(.bottom, 4)
    }

    private var keyGrid: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(0..<rows[r].count, id: \.self) { c in
                            if let g = rows[r][c] {
                                keyButton(g)
                            } else {
                                placeholderKey()
                            }
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
        case .macro(let name): return "macro: \(name)"
        case .disabled: return "(disabled)"
        }
    }

    private func keyButton(_ g: Int) -> some View {
        let display: String
        if let cfg = monitor.config?.gKeys.first(where: { $0.keyNumber == g }) {
            display = actionLabel(for: cfg.action)
        } else {
            display = "—"
        }
        return Button(action: { selectedGKey = g }) {
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

    private func placeholderKey() -> some View {
        Rectangle()
            .foregroundColor(Color.clear)
            .frame(width: 80, height: 60)
    }

    // Thumb keys (non-mappable) representation
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

            if captureMode {
                Text("Press a key on your physical keyboard…")
                    .foregroundColor(.secondary)
                Text(capturedKey.isEmpty ? "(waiting)" : capturedKey)
                    .font(.title3)
                    .padding(.bottom, 4)
                HStack {
                    Button("Use \(capturedKey.isEmpty ? "(none)" : capturedKey)") {
                        if !capturedKey.isEmpty {
                            monitor.updateMapping(for: gKey, action: .keyTap(capturedKey.lowercased()))
                        }
                        captureMode = false
                        capturedKey = ""
                        selectedGKey = nil
                    }.disabled(capturedKey.isEmpty)
                    Button("Cancel") { captureMode = false }
                }
            } else if showMacroList {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select Macro")
                        .font(.subheadline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(config.macros.keys.sorted()), id: \.self) { key in
                                Button(action: {
                                    monitor.updateMapping(for: gKey, action: .macro(key))
                                    showMacroList = false
                                    selectedGKey = nil
                                }) {
                                    VStack(alignment: .leading) {
                                        Text(key).bold()
                                        Text(config.macros[key]?.name ?? "")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(4)
                    }
                    Button("Cancel") { showMacroList = false }
                }
            } else {
                if let current = config.gKeys.first(where: { $0.keyNumber == gKey })?.action {
                    Text("Current: \(actionLabel(for: current))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Map Key") { captureMode = true; capturedKey = "" }
                    Button("Map Macro") { showMacroList = true }
                    Button("Disable") {
                        monitor.updateMapping(for: gKey, action: .disabled)
                        selectedGKey = nil
                    }
                }
                Button("Close") { selectedGKey = nil }
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 360, height: 400)
        .background(.thinMaterial)
        .cornerRadius(16)
        .shadow(radius: 18)
        .overlay(alignment: .topTrailing) {
            Button(action: { selectedGKey = nil }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .onAppear { startCaptureListenerIfNeeded() }
        .onDisappear { stopCaptureListener() }
        // Ensure capture starts if user toggles "Map Key" after overlay already appeared.
        .onChange(of: captureMode) { newValue in
            if newValue {
                startCaptureListenerIfNeeded()
            } else {
                stopCaptureListener()
            }
        }
    }

    // MARK: Key capture using NSEvent local monitor
    private func startCaptureListenerIfNeeded() {
        guard captureMode else { return }
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                if captureMode {
                    capturedKey = normalizeKey(event)
                    // Debug instrumentation so user can see capture events in console.
                    print("[KeyMapEditor] Captured keyCode=\(event.keyCode) mapped=\(capturedKey)")
                    return nil // swallow captured key presses
                }
                return event
            }
        }
    }

    private func stopCaptureListener() {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
    }

    private func normalizeKey(_ event: NSEvent) -> String {
        // Convert characters to lower case; special handling for function keys, escape, etc.
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let scalar = chars.lowercased()
            return specialKeyName(from: event.keyCode) ?? scalar
        }
        return specialKeyName(from: event.keyCode) ?? "unknown"
    }

    private func specialKeyName(from keyCode: UInt16) -> String? {
        // Minimal mapping; extend as needed.
        let mapping: [UInt16: String] = [
            53: "escape", // esc
            48: "tab",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            49: "space",
            36: "return",
            51: "delete",
            117: "forwarddelete",
            123: "left",
            124: "right",
            125: "down",
            126: "up",
            115: "home",
            119: "end",
            116: "pageup",
            121: "pagedown"
        ]
        return mapping[keyCode]
    }
}

@available(macOS 13.0, *)
struct KeyMapEditorView_Previews: PreviewProvider {
    static var previews: some View {
        KeyMapEditorView(monitor: HIDMonitor())
    }
}
