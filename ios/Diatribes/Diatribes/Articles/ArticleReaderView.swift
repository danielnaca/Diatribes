import SwiftUI

struct ArticleReaderView: View {
    let title: String
    let source: String
    let paragraphs: [String]

    @AppStorage("language")          private var language      = "French"
    @AppStorage("highlightsOn")      private var highlightsOn  = true
    @AppStorage("enabledPOSRaw")     private var enabledPOSRaw = "noun,verb,adj,adv"

    @State private var showOptions = false
    @State private var tappedWord: WordTapInfo?

    private var enabledPOS: Set<String> {
        Set(enabledPOSRaw.split(separator: ",").map(String.init))
    }
    private var langCode: String { language == "Spanish" ? "es" : "fr" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.bold())
                    Text(hostName(from: source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                        let swapped = DictSwap.shared.swap(
                            text: para,
                            langCode: langCode,
                            enabledPOS: enabledPOS,
                            highlightsOn: highlightsOn
                        )
                        Text(swapped.attributed)
                            .font(.body)
                            .lineSpacing(4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(hostName(from: source))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "diatribes",
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let en   = comps.queryItems?.first(where: { $0.name == "en"   })?.value,
                  let tr   = comps.queryItems?.first(where: { $0.name == "tr"   })?.value,
                  let pos  = comps.queryItems?.first(where: { $0.name == "pos"  })?.value,
                  let lang = comps.queryItems?.first(where: { $0.name == "lang" })?.value
            else { return .systemAction }
            tappedWord = WordTapInfo(english: en, translation: tr, pos: pos, language: lang)
            return .handled
        })
        .sheet(isPresented: $showOptions) {
            ArticleOptionsSheet()
        }
        .sheet(item: $tappedWord) { info in
            WordPopupSheet(info: info)
        }
    }

    private func hostName(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}

// MARK: - Article options sheet

struct ArticleOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("highlightsOn")  private var highlightsOn  = true
    @AppStorage("enabledPOSRaw") private var enabledPOSRaw = "noun,verb,adj,adv"

    private var enabledPOS: Set<String> {
        Set(enabledPOSRaw.split(separator: ",").map(String.init))
    }

    private func setEnabled(_ key: String, _ on: Bool) {
        var set = enabledPOS
        if on { set.insert(key) } else { set.remove(key) }
        enabledPOSRaw = set.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word swap") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(posTags, id: \.key) { tag in
                            let isOn = enabledPOS.contains(tag.key)
                            Button {
                                setEnabled(tag.key, !isOn)
                            } label: {
                                Text(tag.label)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isOn ? posColor(tag.key) : Color(.systemGray5))
                                    .foregroundStyle(isOn ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Highlights") {
                    Picker("Highlights", selection: $highlightsOn) {
                        Text("On").tag(true)
                        Text("Off").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Article Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func posColor(_ pos: String) -> Color {
        switch pos {
        case "noun": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "verb": return Color(red: 0.086, green: 0.639, blue: 0.239)
        case "adj":  return Color(red: 0.761, green: 0.255, blue: 0.047)
        case "adv":  return Color(red: 0.486, green: 0.231, blue: 0.929)
        default:     return .gray
        }
    }
}
