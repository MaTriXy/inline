import Combine
import InlineKit
import InlineUI
import SwiftUI
import SwiftUIIntrospect

struct ChatView: View {
  // MARK: - Properties

  @EnvironmentStateObject var fullChatViewModel: FullChatViewModel
  @EnvironmentObject var nav: Navigation
  @EnvironmentObject var dataManager: DataManager

  var peer: Peer

  @State private var text: String = ""
  @State private var timer: AnyCancellable?

  // MARK: - Initialization

  init(peer: Peer) {
    self.peer = peer
    _fullChatViewModel = EnvironmentStateObject { env in
      FullChatViewModel(db: env.appDatabase, peer: peer)
    }
  }

  var title: String {
    if case .user = peer {
      return fullChatViewModel.peerUser?.firstName ?? ""
    } else {
      return fullChatViewModel.chat?.title ?? ""
    }
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      chatMessages
      inputArea
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        chatHeader
      }
    }
    .toolbarRole(.editor)
    .toolbar(.hidden, for: .tabBar)
    .onTapGesture(perform: dismissKeyboard)
    .onAppear {
      startPolling()
    }
    .onDisappear {
      stopPolling()
    }
  }

  // MARK: - Polling

  private func startPolling() {
    // Initial fetch
    fetchMessages()

    // Start timer for periodic fetches
    timer = Timer.publish(every: 3, on: .main, in: .common)
      .autoconnect()
      .sink { _ in
        fetchMessages()
      }
  }

  private func stopPolling() {
    timer?.cancel()
    timer = nil
  }

  private func fetchMessages() {
    Task {
      try await dataManager.getChatHistory(
        peerUserId: nil,
        peerThreadId: nil,
        peerId: peer
      )
    }
  }
}

// MARK: - View Components

private extension ChatView {
  var chatMessages: some View {
    MessagesCollectionView(messages: fullChatViewModel.messages)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var chatHeader: some View {
    HStack(spacing: 2) {
      InitialsCircle(firstName: title, lastName: nil, size: 26)
        .padding(.trailing, 6)
      Text(title)
        .font(.title3)
        .fontWeight(.medium)
    }
  }

  var inputArea: some View {
    VStack(spacing: 0) {
      Divider()
        .ignoresSafeArea()
      HStack {
        messageTextField
        sendButton
      }
      .padding()
    }
    .background(.clear)
  }

  var messageTextField: some View {
    TextField("Type a message", text: $text, axis: .vertical)
      .textFieldStyle(.plain)
      .onSubmit(sendMessage)
  }

  var sendButton: some View {
    Button(action: sendMessage) {
      Image(systemName: "arrow.up")
        .foregroundColor(text.isEmpty ? .secondary : .blue)
        .font(.body)
    }
    .disabled(text.isEmpty)
  }
}

// MARK: - Actions

private extension ChatView {
  func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }

  func sendMessage() {
    Task {
      do {
        if !text.isEmpty {
          print("sendMessage Sending message: \(text)")
          print("sendMessage peer : \(peer)")
          try await dataManager.sendMessage(
            chatId: fullChatViewModel.chat?.id ?? 0,
            peerUserId: nil,
            peerThreadId: nil,
            text: text,
            peerId: peer
          )
          text = ""
        }
      } catch {
        Log.shared.error("Failed to send message", error: error)
      }
    }
  }
}

// MARK: - Preview

// #Preview {
//    NavigationStack {
//        ChatView(item: ChatItem(chat: Chat(id: 12344, type: .privateChat, title: "Chat", createdAt: .now(), updatedAt: .now()), user: nil))
//            .appDatabase(.emptyWithChat())
//    }
// }
