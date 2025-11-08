import SwiftUI
import G13HID

@available(macOS 13.0, *)
struct JoystickSettingsView: View {
    @ObservedObject var monitor: HIDMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var workingConfig: JoystickConfig = JoystickConfig()
    @State private var isDirty: Bool = false
    @State private var errorMessage: String? = nil

    // Derived convenience bindings
    private var isDutyCycle: Bool {
        if case .dutyCycle = workingConfig.events { return true } else { return false }
    }
    private var isHoldMode: Bool { !isDutyCycle }

    // Extract duty cycle parameters with defaults
    private var dutyCycleParams: (frequency: Double, ratio: Double, maxEvents: Int?, assist: JoystickDiagonalAssist?) {
        switch workingConfig.events {
        case .dutyCycle(let f, let r, let m, let a): return (f,r,m,a)
        case .hold: return (60.0, 0.5, nil, nil)
        }
    }

    private var holdParams: (diagonalAnglePercent: Double, holdEnabled: Bool, assist: JoystickDiagonalAssist?) {
        switch workingConfig.events {
        case .hold(let pct, let enabled, let assist): return (pct, enabled, assist)
        case .dutyCycle: return (0.15, true, nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Form {
                generalSection
                modeSection
                if isDutyCycle { dutyCycleSection }
                if isDutyCycle { diagonalAssistSection }
                if isHoldMode { holdModeSection }
            }
            actionBar
        }
        .padding(20)
        .onAppear { loadInitial() }
        .frame(minWidth: 540, minHeight: 620)
    }

    private var header: some View {
        HStack {
            Text("Joystick Settings").font(.title2)
            Spacer()
            Button("Close") { dismissIfCleanOrConfirm() }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Enabled", isOn: $workingConfig.enabled.onChange(markDirty))
            HStack {
                Text("Deadzone")
                Slider(value: $workingConfig.deadzone.onChange(markDirty), in: 0.0...0.5, step: 0.01)
                Text(String(format: "%.2f", workingConfig.deadzone)).monospacedDigit()
            }
            VStack(alignment: .leading) {
                Text("Directional Keys").font(.subheadline)
                HStack {
                    keyField(title: "Up", text: $workingConfig.upKey)
                    keyField(title: "Down", text: $workingConfig.downKey)
                    keyField(title: "Left", text: $workingConfig.leftKey)
                    keyField(title: "Right", text: $workingConfig.rightKey)
                }
            }
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Events Mode", selection: Binding(get: { isDutyCycle ? "duty" : "hold" }, set: { newVal in
                withAnimation {
                    if newVal == "duty" {
                        let p = dutyCycleParams
                        workingConfig.events = .dutyCycle(frequency: p.frequency, ratio: p.ratio, maxEventsPerSecond: p.maxEvents, diagonalAssist: p.assist)
                    } else {
                        let h = holdParams
                        workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: h.assist)
                    }
                    markDirty()
                }
            })) {
                Text("Duty Cycle").tag("duty")
                Text("Hold").tag("hold")
            }
            .pickerStyle(.segmented)
        }
    }

    private var dutyCycleSection: some View {
        let p = dutyCycleParams
        return Section("Duty Cycle") {
            HStack {
                Text("Frequency (Hz)")
                Slider(value: Binding(get: { p.frequency }, set: { newVal in
                    updateDutyCycle(frequency: newVal, ratio: p.ratio, maxEvents: p.maxEvents, assist: p.assist)
                }), in: 10...240, step: 1)
                Text(String(format: "%.0f", p.frequency)).monospacedDigit()
            }
            HStack {
                Text("Secondary Ratio")
                Slider(value: Binding(get: { p.ratio }, set: { newVal in
                    updateDutyCycle(frequency: p.frequency, ratio: newVal, maxEvents: p.maxEvents, assist: p.assist)
                }), in: 0.05...1.0, step: 0.01)
                Text(String(format: "%.2f", p.ratio)).monospacedDigit()
            }
            HStack {
                Text("Max Events/sec")
                TextField("(optional)", text: Binding(get: { p.maxEvents.map { String($0) } ?? "" }, set: { newVal in
                    let intVal = Int(newVal)
                    updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: intVal, assist: p.assist)
                }))
                .frame(width: 100)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }

    private var diagonalAssistSection: some View {
        let p = dutyCycleParams
        @State var assistEnabled: Bool = p.assist != nil
        let assist = p.assist ?? JoystickDiagonalAssist()
        return Section("Neutral → Diagonal Assist") {
            Toggle("Enable Assist", isOn: Binding(get: { p.assist != nil }, set: { enabled in
                let newAssist = enabled ? assist : nil
                updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: p.maxEvents, assist: newAssist)
            }))
            if p.assist != nil {
                HStack { Text("Axis Threshold × deadzone") ; Slider(value: Binding(get: { assist.axisThresholdMultiplier }, set: { v in
                    updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: p.maxEvents, assist: JoystickDiagonalAssist(axisThresholdMultiplier: v, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: assist.minSecondaryRatio))
                }), in: 0.5...1.2, step: 0.01); Text(String(format: "%.2f", assist.axisThresholdMultiplier)).monospacedDigit() }
                HStack { Text("Min Angle (°)") ; Slider(value: Binding(get: { assist.minAngleDegrees }, set: { v in
                    updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: p.maxEvents, assist: JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: v, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: assist.minSecondaryRatio))
                }), in: 0.0...30.0, step: 0.5); Text(String(format: "%.1f", assist.minAngleDegrees)).monospacedDigit() }
                HStack { Text("Max Angle (°)") ; Slider(value: Binding(get: { assist.maxAngleDegrees }, set: { v in
                    updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: p.maxEvents, assist: JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: v, minSecondaryRatio: assist.minSecondaryRatio))
                }), in: 20.0...60.0, step: 0.5); Text(String(format: "%.1f", assist.maxAngleDegrees)).monospacedDigit() }
                HStack { Text("Min Secondary Ratio") ; Slider(value: Binding(get: { assist.minSecondaryRatio }, set: { v in
                    updateDutyCycle(frequency: p.frequency, ratio: p.ratio, maxEvents: p.maxEvents, assist: JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: v))
                }), in: 0.1...0.7, step: 0.01); Text(String(format: "%.2f", assist.minSecondaryRatio)).monospacedDigit() }
            }
        }
    }

    private var holdModeSection: some View {
        let h = holdParams
        let assist = h.assist ?? JoystickDiagonalAssist()
        return Section("Hold Mode") {
            Toggle("Hold Enabled", isOn: Binding(get: { h.holdEnabled }, set: { newVal in
                workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: newVal, diagonalAssist: h.assist)
                markDirty()
            }))
            HStack {
                Text("Diagonal Angle %")
                Slider(value: Binding(get: { h.diagonalAnglePercent }, set: { newVal in
                    workingConfig.events = .hold(diagonalAnglePercent: newVal, holdEnabled: h.holdEnabled, diagonalAssist: h.assist)
                    markDirty()
                }), in: 0.05...0.40, step: 0.01)
                Text(String(format: "%.2f", h.diagonalAnglePercent)).monospacedDigit()
            }
            Divider()
            Text("Neutral → Diagonal Assist")
                .font(.subheadline)
                .padding(.top, 4)
            Toggle("Enable Assist", isOn: Binding(get: { h.assist != nil }, set: { enabled in
                let newAssist = enabled ? assist : nil
                workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: newAssist)
                markDirty()
            }))
            if h.assist != nil {
                HStack { Text("Axis Threshold × deadzone") ; Slider(value: Binding(get: { assist.axisThresholdMultiplier }, set: { v in
                    let updated = JoystickDiagonalAssist(axisThresholdMultiplier: v, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: assist.minSecondaryRatio)
                    workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: updated)
                    markDirty()
                }), in: 0.5...1.2, step: 0.01); Text(String(format: "%.2f", assist.axisThresholdMultiplier)).monospacedDigit() }
                HStack { Text("Min Angle (°)") ; Slider(value: Binding(get: { assist.minAngleDegrees }, set: { v in
                    let updated = JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: v, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: assist.minSecondaryRatio)
                    workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: updated)
                    markDirty()
                }), in: 0.0...30.0, step: 0.5); Text(String(format: "%.1f", assist.minAngleDegrees)).monospacedDigit() }
                HStack { Text("Max Angle (°)") ; Slider(value: Binding(get: { assist.maxAngleDegrees }, set: { v in
                    let updated = JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: v, minSecondaryRatio: assist.minSecondaryRatio)
                    workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: updated)
                    markDirty()
                }), in: 20.0...60.0, step: 0.5); Text(String(format: "%.1f", assist.maxAngleDegrees)).monospacedDigit() }
                HStack { Text("Min Secondary Ratio") ; Slider(value: Binding(get: { assist.minSecondaryRatio }, set: { v in
                    let updated = JoystickDiagonalAssist(axisThresholdMultiplier: assist.axisThresholdMultiplier, minAngleDegrees: assist.minAngleDegrees, maxAngleDegrees: assist.maxAngleDegrees, minSecondaryRatio: v)
                    workingConfig.events = .hold(diagonalAnglePercent: h.diagonalAnglePercent, holdEnabled: h.holdEnabled, diagonalAssist: updated)
                    markDirty()
                }), in: 0.1...0.7, step: 0.01); Text(String(format: "%.2f", assist.minSecondaryRatio)).monospacedDigit() }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let msg = errorMessage { Text(msg).foregroundColor(.red) }
            Spacer()
            Button("Revert") { revertChanges() }.disabled(!isDirty)
            Button("Save") { saveChanges() }.disabled(!isDirty)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers
    private func keyField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            TextField(title, text: text.onChange(markDirty))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
        }
    }

    private func updateDutyCycle(frequency: Double, ratio: Double, maxEvents: Int?, assist: JoystickDiagonalAssist?) {
        workingConfig.events = .dutyCycle(frequency: frequency, ratio: ratio, maxEventsPerSecond: maxEvents, diagonalAssist: assist)
        markDirty()
    }

    private func loadInitial() {
        if let cfg = monitor.config?.joystick { workingConfig = cfg } else { workingConfig = JoystickConfig() }
        isDirty = false
    }

    private func revertChanges() { loadInitial() }

    private func saveChanges() {
        monitor.updateJoystickConfig(workingConfig)
        isDirty = false
    }

    private func dismissIfCleanOrConfirm() {
        if isDirty { revertChanges() }
        dismiss()
    }

    private func markDirty() { isDirty = true }
}

@available(macOS 13.0, *)
private struct JoystickSettingsView_Previews: PreviewProvider {
    static var previews: some View { JoystickSettingsView(monitor: HIDMonitor()) }
}

// Binding extension to observe changes
extension Binding {
    func onChange(_ handler: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { newVal in
            wrappedValue = newVal
            handler()
        })
    }
}
