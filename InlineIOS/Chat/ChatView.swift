import Combine
import InlineKit
import InlineUI
import SwiftUI

struct ChatView: View {
  var peerId: Peer

  @State var text: String = ""
  @State var textViewHeight: CGFloat = 36
  @State var appearFakeChat = false

  @EnvironmentStateObject var fullChatViewModel: FullChatViewModel
  @EnvironmentObject var nav: Navigation
  @EnvironmentObject var data: DataManager
  @EnvironmentObject var ws: WebSocketManager

  @Environment(\.appDatabase) var database
  @Environment(\.scenePhase) var scenePhase

  @ObservedObject var composeActions: ComposeActions = .shared

  func currentComposeAction() -> ApiComposeAction? {
    composeActions.getComposeAction(for: peerId)?.action
  }

  @State var currentTime = Date()

  let timer = Timer.publish(
    every: 60, // 1 minute
    on: .main,
    in: .common
  ).autoconnect()

  static let formatter = RelativeDateTimeFormatter()
  func getLastOnlineText(date: Date?) -> String {
    guard let date = date else { return "" }

    let diffSeconds = Date().timeIntervalSince(date)
    if diffSeconds < 60 {
      return "last seen just now"
    }

    Self.formatter.dateTimeStyle = .named
    //    Self.formatter.unitsStyle = .spellOut
    return "last seen \(Self.formatter.localizedString(for: date, relativeTo: Date()))"
  }

  var subtitle: String {
    // TODO: support threads
    if ws.connectionState == .connecting {
      return "connecting..."
    } else if let composeAction = currentComposeAction() {
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
    self.peerId = peer
    _fullChatViewModel = EnvironmentStateObject { env in
      FullChatViewModel(db: env.appDatabase, peer: peer, limit: 50, fetchesMessages: true)
    }
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      if !appearFakeChat {
        content
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
                    Task { await ComposeActions.shared.stoppedTyping(for: peerId) }
                  } else {
                    Task { await ComposeActions.shared.startedTyping(for: peerId) }
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
            }
            .padding(.vertical, 6)
            .padding(.horizontal)
            .background(Color(uiColor: .systemBackground))
          }
      } else {
        FakeChatView(
          text: $text,
          textViewHeight: $textViewHeight,
          peerId: peerId
        )
      }
    }
    .onReceive(timer) { _ in
      currentTime = Date()
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

      ToolbarItem(placement: .topBarTrailing) {
        Button("👻") {
          withAnimation {
            appearFakeChat.toggle()
          }
        }
      }
    }
    .navigationBarHidden(false)
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarTitleDisplayMode(.inline)
    .onAppear {
      Task {
        await fetch()
      }
    }
    .onChange(of: scenePhase) { _, scenePhase_ in
      switch scenePhase_ {
      case .active:
        Task {
          await fetch()
        }
      default:
        break
      }
    }
  }

  func fetch() async {
    do {
      try await data.getChatHistory(peerUserId: nil, peerThreadId: nil, peerId: peerId)
    } catch {
      Log.shared.error("Failed to get chat history", error: error)
    }
  }
}

struct CustomButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.8 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
