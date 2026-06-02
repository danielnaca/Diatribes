import SwiftUI

struct ChatOptionsSheet: View {
    @EnvironmentObject private var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                posSection
                densitySection
                highlightsSection
                correctionsSection
                answerLengthSection
                speedSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Chat Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: POS pills

    private var posSection: some View {
        Section("Word swap") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(posTags, id: \.key) { tag in
                    POSPill(label: tag.label, key: tag.key, vm: vm)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Density

    private var densitySection: some View {
        Section {
            VStack(spacing: 8) {
                Slider(value: $vm.wordDensity, in: 0...1, step: 0.25)
                    .tint(Color(red: 188/255, green: 130/255, blue: 0))
                HStack {
                    Text("None").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(densityLabel).font(.caption.weight(.medium))
                    Spacer()
                    Text("All").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Word density")
        } footer: {
            Text("Fraction of eligible words actually swapped")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var densityLabel: String {
        switch vm.wordDensity {
        case 0:    return "None"
        case 0.25: return "Few"
        case 0.5:  return "Half"
        case 0.75: return "Most"
        default:   return "All"
        }
    }

    // MARK: Highlights

    private var highlightsSection: some View {
        Section("Highlights") {
            Picker("Highlights", selection: $vm.highlightsOn) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Corrections

    private var correctionsSection: some View {
        Section("Corrections") {
            Picker("Corrections", selection: $vm.correctionMode) {
                ForEach(CorrectionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Answer length

    private var answerLengthSection: some View {
        Section("Answer length") {
            Picker("Answer length", selection: $vm.responseLength) {
                Text("Brief").tag(1)
                Text("Medium").tag(3)
                Text("Long").tag(5)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Speed

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Slow").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $vm.speed, in: 0.5...2.0, step: 0.25)
                    Text("Fast").font(.caption).foregroundStyle(.secondary)
                }
                Text(String(format: "%.2gx", vm.speed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Speed")
        } footer: {
            Text("Google voices only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - POS pill

private struct POSPill: View {
    let label: String
    let key: String
    @ObservedObject var vm: ChatViewModel

    private var isOn: Bool { vm.enabledPOS.contains(key) }

    private var pillColor: Color {
        switch key {
        case "noun": return Color(red: 0.145, green: 0.388, blue: 0.922) // #2563eb
        case "verb": return Color(red: 0.086, green: 0.639, blue: 0.239) // #16a34a
        case "adj":  return Color(red: 0.761, green: 0.255, blue: 0.047) // #c2410c
        case "adv":  return Color(red: 0.486, green: 0.231, blue: 0.929) // #7c3aed
        default:     return .gray
        }
    }

    var body: some View {
        Button {
            if isOn {
                vm.enabledPOS.remove(key)
            } else {
                vm.enabledPOS.insert(key)
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? pillColor : Color(.systemGray5))
                .foregroundStyle(isOn ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
