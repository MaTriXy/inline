import Combine
import InlineKit
import InlineUI
import SwiftUI

struct ChatView: View {
  var peer: Peer

  @State var text: String = ""
  @State private var textViewHeight: CGFloat = 36

  @EnvironmentStateObject var fullChatViewModel: FullChatViewModel
  @EnvironmentObject var nav: Navigation
  @EnvironmentObject var dataManager: DataManager
  @Environment(\.appDatabase) var database
  @Environment(\.scenePhase) var scenePhase

  @ObservedObject var composeActions: ComposeActions = .shared

  private func currentComposeAction() -> ApiComposeAction? {
    composeActions.getComposeAction(for: peer)?.action
  }

  static let formatter = RelativeDateTimeFormatter()
  private func getLastOnlineText(date: Date?) -> String {
    guard let date = date else { return "" }
    Self.formatter.dateTimeStyle = .named
    return "last seen \(Self.formatter.localizedString(for: date, relativeTo: Date()))"
  }

  var subtitle: String {
    if let composeAction = currentComposeAction() {
      return composeAction.rawValue
    } else if let online = fullChatViewModel.peerUser?.online {
      return online
        ? "online"
        : (fullChatViewModel.peerUser?.lastOnline != nil
          ? getLastOnlineText(date: fullChatViewModel.peerUser?.lastOnline) : "offline")
    } else {
      return "last seen recently"
    }
  }

  init(peer: Peer) {
    self.peer = peer
    _fullChatViewModel = EnvironmentStateObject { env in
      FullChatViewModel(db: env.appDatabase, peer: peer, limit: 80)
    }
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      MessagesCollectionView(fullMessages: fullChatViewModel.fullMessages.reversed())
        .safeAreaInset(edge: .bottom) {
          HStack(alignment: .bottom) {
            ZStack(alignment: .leading) {
              TextView(
                text: $text,
                height: $textViewHeight
              )

              .frame(height: textViewHeight)
              .background(.clear)
              .onChange(of: text) { newText in
                if newText.isEmpty {
                  Task { await ComposeActions.shared.stoppedTyping(for: peer) }
                } else {
                  Task { await ComposeActions.shared.startedTyping(for: peer) }
                }
              }
              if text.isEmpty {
                Text("Write a message")
                  .foregroundStyle(.tertiary)
                  .padding(.leading, 6)
                  .padding(.vertical, 6)
                  .allowsHitTesting(false)
                  .transition(
                    .asymmetric(
                      insertion: .offset(x: 40).combined(with: .opacity),
                      removal: .offset(x: 40).combined(with: .opacity)
                    )
                  )
              }
            }
            .animation(.smoothSnappy, value: textViewHeight)
            .animation(.smoothSnappy, value: text.isEmpty)

            sendButton
              .padding(.bottom, 6)

            //  inputArea
          }
          .padding(.vertical, 6)
          .padding(.horizontal)
          .background(Color(uiColor: .systemBackground))
        }
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack {
          Text(title)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      #if DEBUG
        ToolbarItem(placement: .topBarTrailing) {
          Button("Debug") {
            sendDebugMessages()
          }
        }
      #endif
    }
    .navigationBarHidden(false)
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarTitleDisplayMode(.inline)
    .onAppear {
      fetchMessages()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        fetchMessages()
      }
    }
  }
}

// MARK: - Helper Methods

extension ChatView {
  private func fetchMessages() {
    Task {
      do {
        try await dataManager.getChatHistory(
          peerUserId: nil,
          peerThreadId: nil,
          peerId: peer
        )
      } catch {
        Log.shared.error("Failed to fetch messages", error: error)
      }
    }
  }

  private func dismissKeyboard() {
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let chatId = fullChatViewModel.chat?.id else { return }

        let messageText = text

        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()

        // Delay clearing the text field to allow animation to complete
        withAnimation {
          text = ""
          textViewHeight = 36
        }

        let peerUserId: Int64? = if case .user(let id) = peer { id } else { nil }
        let peerThreadId: Int64? = if case .thread(let id) = peer { id } else { nil }

        let randomId = Int64.random(in: Int64.min...Int64.max)
        let message = Message(
          messageId: -randomId,
          randomId: randomId,
          fromId: Auth.shared.getCurrentUserId()!,
          date: Date(),
          text: messageText,
          peerUserId: peerUserId,
          peerThreadId: peerThreadId,
          chatId: chatId,
          out: true,
          status: .sending,
          repliedToMessageId: ChatState.shared.getState(chatId: chatId).replyingMessageId
        )

        // Save message to database
        try await database.dbWriter.write { db in
          try message.save(db)
        }

        // Send message to server
        try await dataManager.sendMessage(
          chatId: chatId,
          peerUserId: peerUserId,
          peerThreadId: peerThreadId,
          text: messageText,
          peerId: peer,
          randomId: randomId,
          repliedToMessageId: ChatState.shared.getState(chatId: chatId).replyingMessageId
        )
      } catch {
        Log.shared.error("Failed to send message", error: error)
        // Optionally show error to user
      }
    }
  }

  private func sendDebugMessages() {
    Task {
      guard let chatId = fullChatViewModel.chat?.id else { return }

      // Send 80 messages with different lengths
      for i in 1...200 {
        let messageLength = Int.random(in: 10...200)
        let messageText = String(repeating: "Test message \(i) ", count: messageLength / 10)

        let peerUserId: Int64? = if case .user(let id) = peer { id } else { nil }
        let peerThreadId: Int64? = if case .thread(let id) = peer { id } else { nil }

        let randomId = Int64.random(in: Int64.min...Int64.max)
        let message = Message(
          messageId: -randomId,
          randomId: randomId,
          fromId: Auth.shared.getCurrentUserId()!,
          date: Date(),
          text: messageText,
          peerUserId: peerUserId,
          peerThreadId: peerThreadId,
          chatId: chatId,
          out: true,
          status: .sending,
          repliedToMessageId: nil
        )

        do {
          // Save to database
          try await database.dbWriter.write { db in
            try message.save(db)
          }

          // Send to server
          try await dataManager.sendMessage(
            chatId: chatId,
            peerUserId: peerUserId,
            peerThreadId: peerThreadId,
            text: messageText,
            peerId: peer,
            randomId: randomId,
            repliedToMessageId: nil
          )

          // Add small delay between messages
          try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        } catch {
          Log.shared.error("Failed to send debug message", error: error)
        }
      }
    }
  }
}

// MARK: - Helper Properties

extension ChatView {
  var title: String {
    if case .user = peer {
      return fullChatViewModel.peerUser?.firstName ?? ""
    } else {
      return fullChatViewModel.chat?.title ?? ""
    }
  }
}

// MARK: - Views

extension ChatView {
  @ViewBuilder
  private var chatMessages: some View {
    MessagesCollectionView(fullMessages: fullChatViewModel.fullMessages)
  }

  @ViewBuilder
  var sendButton: some View {
    Button {
      sendMessage()
    } label: {
      Circle()
        .fill(text.isEmpty ? Color(.systemGray5) : .blue)
        .frame(width: 28, height: 28)
        .overlay {
          Image(systemName: "paperplane.fill")
            .font(.callout)
            .foregroundStyle(text.isEmpty ? Color(.tertiaryLabel) : .white)
        }
    }

    .buttonStyle(CustomButtonStyle())
  }
}

struct CustomButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.8 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
