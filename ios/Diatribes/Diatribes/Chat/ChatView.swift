import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var vm: ChatViewModel
    @State private var tappedWord: WordTapInfo?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
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
            }
            .sheet(item: $tappedWord) { info in
                WordPopupSheet(info: info)
            }
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
            .onTapGesture { isInputFocused = false }
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
                tappedWord = WordTapInfo(english: en, translation: tr, pos: pos, language: lang)
                return .handled
            })
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                inputPill
                actionButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }

    // Switches between text field, waveform (recording), and thinking state
    private var inputPill: some View {
        ZStack {
            if vm.isRecording {
                HStack(spacing: 10) {
                    WaveformView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                    Text("Listening…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if vm.isProcessing {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Thinking…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
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
                } else if vm.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
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
        }
        .disabled(vm.isProcessing)
        .padding(.top, 6)
        .padding(.trailing, 6)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: vm.isRecording)
        .animation(.easeInOut(duration: 0.15), value: vm.isProcessing)
        .animation(.easeInOut(duration: 0.15), value: vm.inputText.isEmpty)
    }
}

// MARK: - Waveform

struct WaveformView: View {
    private let targets: [CGFloat] = [
        10, 22, 16, 28, 8, 24, 14, 26, 6, 20, 18, 28, 12, 24, 8,
        22, 16, 28, 10, 20, 14, 26, 6, 22, 18, 28, 12, 24, 8, 20
    ]
    @State private var active = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(targets.enumerated()), id: \.offset) { i, target in
                WaveformBar(target: target, index: i, active: active)
            }
        }
        .onAppear { active = true }
        .onDisappear { active = false }
    }
}

private struct WaveformBar: View {
    let target: CGFloat
    let index: Int
    let active: Bool

    var body: some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: 3, height: active ? target : 4)
            .animation(
                .easeInOut(duration: 0.35 + Double(index % 5) * 0.06)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.025),
                value: active
            )
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
