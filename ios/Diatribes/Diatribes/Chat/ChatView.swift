import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var vm: ChatViewModel
    @State private var tappedWord: WordTapInfo?
    @State private var subTab = 0   // 0 = Speak, 1 = Words
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                subTabBar
                if subTab == 0 {
                    messageList
                    Divider()
                    inputBar
                } else {
                    wordsList
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showChatOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $vm.showChatOptions) {
                ChatOptionsSheet()
                    .environmentObject(vm)
                    .presentationBackground(.white)
            }
            .sheet(item: $tappedWord) { info in
                WordPopupSheet(info: info)
                    .presentationBackground(.white)
            }
        }
    }

    // MARK: Sub-tab bar

    private var subTabBar: some View {
        HStack(spacing: 0) {
            subTabButton("Speak", tag: 0)
            subTabButton("Words", tag: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func subTabButton(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { subTab = tag }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if tag == 1 && !vm.collectedWords.isEmpty {
                    Text("\(vm.collectedWords.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 188/255, green: 130/255, blue: 0))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(subTab == tag ? Color(.systemGray5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(subTab == tag ? .primary : .secondary)
    }

    // MARK: Words list

    private var wordsList: some View {
        Group {
            if vm.collectedWords.isEmpty {
                ContentUnavailableView(
                    "No words yet",
                    systemImage: "character.bubble",
                    description: Text("Tap any highlighted word in the conversation to save it here.")
                )
            } else {
                List {
                    ForEach(vm.collectedWords) { info in
                        Button {
                            tappedWord = info
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.translation)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(posColor(info.pos))
                                    Text(info.english)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(posLabel(info.pos))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(posColor(info.pos).opacity(0.12))
                                    .foregroundStyle(posColor(info.pos))
                                    .clipShape(Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func posLabel(_ pos: String) -> String {
        switch pos {
        case "noun": return "Noun"
        case "verb": return "Verb"
        case "adj":  return "Adj"
        case "adv":  return "Adv"
        default:     return pos
        }
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
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
                let info = WordTapInfo(english: en, translation: tr, pos: pos, language: lang)
                vm.collectWord(info)
                tappedWord = info
                return .handled
            })
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                inputPill
                actionButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }

    private var inputPill: some View {
        ZStack {
            if vm.isRecording {
                WaveformView(level: vm.audioLevel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if vm.isProcessing {
                ProgressView()
                    .scaleEffect(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            } else {
                TextField("Message…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onSubmit { vm.sendText() }
                    .transition(.opacity)
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.2), value: vm.isRecording)
        .animation(.easeInOut(duration: 0.2), value: vm.isProcessing)
    }

    private var actionButton: some View {
        Button {
            isInputFocused = false
            if vm.isRecording {
                vm.toggleRecording()
            } else if !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                vm.sendText()
            } else {
                vm.toggleRecording()
            }
        } label: {
            Group {
                if vm.isRecording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                } else if !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(vm.isRecording ? Color.red : Color.primary)
            .clipShape(Circle())
            .opacity(vm.isProcessing ? 0.4 : 1.0)
        }
        .disabled(vm.isProcessing)
        .animation(.easeInOut(duration: 0.15), value: vm.isRecording)
        .animation(.easeInOut(duration: 0.15), value: vm.isProcessing)
        .animation(.easeInOut(duration: 0.15), value: vm.inputText.isEmpty)
    }
}

// MARK: - Waveform (real mic levels)

struct WaveformView: View {
    let level: Float
    @State private var multipliers: [CGFloat] = (0..<26).map { _ in CGFloat.random(in: 0.25...1.0) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, mult in
                Capsule()
                    .fill(Color(.systemGray3))
                    .frame(width: 3, height: max(4, CGFloat(level) * 28 * mult + 4))
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant:
                assistantText
            case .correction:
                correctionBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var userBubble: some View {
        Text(message.text)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .trailing)
    }

    private var assistantText: some View {
        Group {
            if let attr = message.attributed {
                Text(attr)
            } else {
                Text(message.text)
            }
        }
        .font(.body)
        .padding(.vertical, 2)
    }

    private var correctionBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CORRECTION")
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .frame(width: 3)
                .foregroundStyle(Color(.systemGray3))
        }
        .padding(.leading, 4)
    }
}
