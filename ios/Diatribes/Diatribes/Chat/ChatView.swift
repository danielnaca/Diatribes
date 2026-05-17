import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var vm: ChatViewModel

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
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: iMessage-style input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onSubmit { vm.sendText() }

                actionButton
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }

    private var actionButton: some View {
        Button {
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
        }
        .disabled(vm.isProcessing)
        .padding(.trailing, 6)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: vm.isRecording)
        .animation(.easeInOut(duration: 0.15), value: vm.inputText.isEmpty)
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
