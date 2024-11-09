import Combine
import GRDB

public final class FullChatViewModel: ObservableObject {
  @Published public private(set) var chat: Chat?
  @Published public private(set) var messages: [Message] = []
  @Published public private(set) var peerUser: User?

  private var chatCancellable: AnyCancellable?
  private var messagesCancellable: AnyCancellable?
  private var peerUserCancellable: AnyCancellable?

  private var db: AppDatabase
  private var peer: Peer

  public init(db: AppDatabase, peer: Peer) {
    self.db = db
    self.peer = peer
    fetchChat()
    fetchMessages()
  }

  public func fetchChat() {
    switch peer {
    case let .thread(id):
      fetchThreadChat(id)
    case let .user(id):
      fetchPrivateChat(id)
      fetchPeerUser(id)
    }
  }

  func fetchMessages() {
    guard let chatId = chat?.id else { return }

    messagesCancellable =
      ValueObservation
      .tracking { db in
        try Message.filter(Column("chatId") == chatId)
          .order(Column("date").desc)
          .fetchAll(db)
      }
      .publisher(in: db.dbWriter, scheduling: .immediate)
      .sink(
        receiveCompletion: { _ in /* ignore error */ },
        receiveValue: { [weak self] messages in
          self?.messages = messages
        }
      )
  }

  private func fetchThreadChat(_ chatId: Int64) {
    chatCancellable =
      ValueObservation
      .tracking { db in
        try Chat.fetchOne(db, id: chatId)
      }
      .publisher(in: db.dbWriter, scheduling: .immediate)
      .sink(
        receiveCompletion: { _ in /* ignore error */ },
        receiveValue: { [weak self] chat in
          self?.chat = chat
          if chat != nil {
            self?.fetchMessages()
          }
        }
      )
  }

  private func fetchPrivateChat(_ userId: Int64) {
    chatCancellable =
      ValueObservation
      .tracking { db in
        try Chat
          //                    .filter(Column("type") == ChatType.privateChat.rawValue)
          .filter(Column("peerUserId") == userId)
          .fetchOne(db)
      }
      .publisher(in: db.dbWriter, scheduling: .immediate)
      .sink(
        receiveCompletion: { _ in /* ignore error */ },
        receiveValue: { [weak self] chat in
          self?.chat = chat
          if chat != nil {
            self?.fetchMessages()
          }
        }
      )
  }

  public func fetchPeerUser(_ userId: Int64) {
    peerUserCancellable =
      ValueObservation
      .tracking { db in
        print("peer user id : \(userId)")
        return try User.fetchOne(db, id: userId)
      }
      .publisher(in: db.dbWriter, scheduling: .immediate)
      .sink(
        receiveCompletion: { _ in /* ignore error */ },
        receiveValue: { [weak self] user in
          print("Fetched user : \(user)")
          self?.peerUser = user
        }
      )
  }
}
