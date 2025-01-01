import Combine
import GRDB

/// todos
/// - listen to changes of count to first id - last id to detect new messages in between
/// - do a refetch on update instead of manually checking things (90/10)
/// -

@MainActor
public class MessagesProgressiveViewModel {
  // props
  public var peer: Peer

  // state
  public var messagesByID: [Int64: FullMessage] = [:]
  public var messages: [FullMessage] = [] { didSet {
    messagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })

  }}
  public var reversed: Bool = false

  // note: using date is most reliable as our sorting is based on date
  public var minDate: Date = .init()
  public var maxDate: Date = .init()

  // internals
  private let initialLimit = 50
  private let log = Log.scoped("MessagesViewModel", enableTracing: true)
  private let db = AppDatabase.shared
  private var cancellable = Set<AnyCancellable>()
  private var callback: ((_ changeSet: MessagesChangeSet) -> Void)?

  // Note:
  // limit, cursor, range, etc are internals to this module. the view layer should not care about this.
  public init(peer: Peer, reversed: Bool = false) {
    self.peer = peer
    self.reversed = reversed
    // get initial batch
    loadMessages(.limit(initialLimit))

    // subscribe to changes
    MessagesPublisher.shared.publisher
      .sink { [weak self] update in
        guard let self = self else { return }
        Log.shared.debug("Received update \(update)")
        if let changeset = applyChanges(update: update) {
          callback?(changeset)
        }
      }
      .store(in: &cancellable)
  }

  // Set an observer to update the UI
  public func observe(_ callback: @escaping (MessagesChangeSet) -> Void) {
    if self.callback != nil {
      Log.shared.warning("Callback already set, re-setting it to a new one will result in undefined behaviour")
    }

    self.callback = callback
  }

  public enum MessagesLoadDirection {
    case top
    case bottom
  }

  public func loadBatch(at direction: MessagesLoadDirection) {
    // top id as cursor?
    // firs try lets use date as cursor
    let cursor = direction == .top ? minDate : maxDate
    let limit = messages.count > 300 ? 400 : messages.count > 200 ? 300 : 100
    let prepend = direction == (reversed ? .bottom : .top)
    log.debug("Loading next batch at \(direction) \(cursor)")
    loadAdditionalMessages(limit: limit, cursor: cursor, prepend: prepend)
  }

  public enum MessagesChangeSet {
    // TODO: case prepend...
    case added([FullMessage], indexSet: [Int])
    case updated([FullMessage], indexSet: [Int])
    case deleted([Int64], indexSet: [Int])
    case reload
  }

  private func applyChanges(update: MessagesPublisher.UpdateType) -> MessagesChangeSet? {
    log.trace("Applying changes: \(update)")
    switch update {
    case .add(let messageAdd):
      if messageAdd.peer == peer {
        // Check if we have it to not add it again
        let existingIds = Set(messages.map { $0.id })
        if messageAdd.messages.contains(where: { existingIds.contains($0.id) }) {
          log.warning("Message already exists in the list, but message added was triggered.")
          return nil
        }

        // TODO: detect if we should add to the bottom or top
        if reversed {
          messages.insert(contentsOf: messageAdd.messages, at: 0)
        } else {
          messages.append(contentsOf: messageAdd.messages)
        }
        // sort again
        sort()
        updateRange()

        // Return changeset
        return MessagesChangeSet.added(messageAdd.messages, indexSet: [messages.count - 1])
      }

    case .delete(let messageDelete):
      if messageDelete.peer == peer {
        let deletedIndices = messages.enumerated()
          .filter { messageDelete.messageIds.contains($0.element.id) }
          .map { $0.offset }

        // Store indices in reverse order to safely remove items
        let sortedIndices = deletedIndices.sorted(by: >)

        // Remove messages
        sortedIndices.forEach { messages.remove(at: $0) }

        // Update ange
        updateRange()

        // Return changeset
        return MessagesChangeSet.deleted(messageDelete.messageIds, indexSet: sortedIndices)
      }

    case .update(let messageUpdate):
      if messageUpdate.peer == peer {
        guard let index = messages.firstIndex(where: { $0.id == messageUpdate.message.id }) else {
          // not in our range
          return nil
        }

        messages[index] = messageUpdate.message
        updateRange() // ??
        return MessagesChangeSet.updated([messageUpdate.message], indexSet: [index])
      }

    case .reload(let peer):
      if peer == self.peer {
        // 90/10 solution TODO: quick way to optimize is to check if updated messages are in the current range
        refetchCurrentRange()
        // check if actually anything changed then post update

        return MessagesChangeSet.reload
      }
    }

    return nil
  }

  private func sort() {
    if reversed {
      messages = messages.sorted(by: { $0.message.date > $1.message.date })
    } else {
      messages = messages.sorted(by: { $0.message.date < $1.message.date })
    }
  }

  private func sort(batch: [FullMessage]) -> [FullMessage] {
    if reversed {
      batch.sorted(by: { $0.message.date > $1.message.date })
    } else {
      batch.sorted(by: { $0.message.date < $1.message.date })
    }
  }

  // TODO: make it O(1) instead of O(n)
  private func updateRange() {
    var lowestDate = Date.distantFuture
    var highestDate = Date.distantPast

    for message in messages {
      let date = message.message.date
      if date < lowestDate {
        lowestDate = date
      }
      if date > highestDate {
        highestDate = date
      }
    }

    minDate = lowestDate
    maxDate = highestDate

    log.trace("Updated range: \(lowestDate) - \(highestDate), (count: \(messages.count))")
  }

  private func refetchCurrentRange() {
    loadMessages(.preserveRange)
  }

  private enum LoadMode {
    case limit(Int)
    case preserveRange
  }

  private func loadMessages(_ loadMode: LoadMode) {
    let peer = self.peer
    let prevCount = messages.count

    log
      .debug(
        "Loading messages for \(peer) with mode: \(loadMode)"
      )

    do {
      let messagesBatch: [FullMessage] = try db.dbWriter.read { db in
        var query = baseQuery()

        query = query.order(Column("date").desc)

        switch loadMode {
        case .limit(let limit):
          query = query.limit(limit)

        case .preserveRange:
          query = query
            .filter(Column("date") >= minDate)
            .filter(Column("date") <= maxDate)
            .limit(prevCount)
        }

        return try query.fetchAll(db)
      }

      log.trace("loaded messages: \(messagesBatch.count)")
      if reversed {
        // it's actually already reversed bc of our .order above
        messages = messagesBatch
      } else {
        messages = messagesBatch.reversed() // reverse it back
      }

      // Uncomment if we want to sort in SQL based on anything other than date
      // sort()

      updateRange()
    } catch {
      Log.shared.error("Failed to get messages \(error)")
    }
  }

  private func loadAdditionalMessages(limit: Int, cursor: Date, prepend: Bool) {
    let peer = self.peer

    log
      .debug(
        "Loading additional messages for \(peer)"
      )

    do {
      var messagesBatch: [FullMessage] = try db.dbWriter.read { db in
        var query = baseQuery()

        if prepend {
          query = query.order(Column("date").desc)
          query = query.filter(Column("date") <= cursor)
        } else {
          query = query.order(Column("date").asc)
          query = query.filter(Column("date") >= cursor)
        }

        query = query.limit(limit)

        return try query.fetchAll(db)
      }

      log.trace("loaded additional messages: \(messagesBatch.count)")

      messagesBatch = sort(batch: messagesBatch)

      // dedup those with exact date as cursor as they might be included in both
      let existingMessagesAtCursor = Set(messages.filter { $0.message.date == cursor }.map { $0.id })
      messagesBatch.removeAll { existingMessagesAtCursor.contains($0.id) }

      if prepend {
        messages.insert(contentsOf: messagesBatch, at: 0)
      } else {
        messages.append(contentsOf: messagesBatch)
      }

      updateRange()
    } catch {
      Log.shared.error("Failed to get messages \(error)")
    }
  }

  private func baseQuery() -> QueryInterfaceRequest<FullMessage> {
    var query = Message
      .including(optional: Message.from)
      .including(all: Message.reactions)
      .asRequest(of: FullMessage.self)

    switch peer {
    case .thread(let id):
      query = query
        .filter(Column("peerThreadId") == id)
    case .user(let id):
      query = query
        .filter(Column("peerUserId") == id)
    }
    return query
  }
}

@MainActor
public final class MessagesPublisher {
  static let shared = MessagesPublisher()

  public struct MessageUpdate {
    public let message: FullMessage
    let peer: Peer
  }

  public struct MessageAdd {
    public let messages: [FullMessage]
    let peer: Peer
  }

  public struct MessageDelete {
    public let messageIds: [Int64]
    let peer: Peer
  }

  public enum UpdateType {
    case add(MessageAdd)
    case update(MessageUpdate)
    case delete(MessageDelete)
    case reload(peer: Peer)
  }

  private let db = AppDatabase.shared
  let publisher = PassthroughSubject<UpdateType, Never>()

  // Static methods to publish update
  func messageAdded(message: Message, peer: Peer) {
    Log.shared.debug("Message added: \(message.messageId)")
    let fullMessage = try? db.reader.read { db in
      try Message
        .filter(Column("globalId") == message.globalId)
        .including(optional: Message.from)
        .including(all: Message.reactions)
        .asRequest(of: FullMessage.self)
        .fetchOne(db)
    }
    guard let fullMessage = fullMessage else {
      Log.shared.error("Failed to get full message")
      return
    }
    publisher.send(.add(MessageAdd(messages: [fullMessage], peer: peer)))
  }

  func messagesDeleted(messageIds: [Int64], peer: Peer) {
    publisher.send(.delete(MessageDelete(messageIds: messageIds, peer: peer)))
  }

  func messageUpdated(message: Message, peer: Peer) {
    Log.shared.debug("Message updated: \(message.messageId)")
    let fullMessage = try? db.reader.read { db in
      try Message
        .filter(Column("globalId") == message.globalId)
        .including(optional: Message.from)
        .including(all: Message.reactions)
        .asRequest(of: FullMessage.self)
        .fetchOne(db)
    }
    guard let fullMessage = fullMessage else {
      Log.shared.error("Failed to get full message")
      return
    }
    publisher.send(.update(MessageUpdate(message: fullMessage, peer: peer)))
  }

  func messagesReload(peer: Peer) {
    publisher.send(.reload(peer: peer))
  }
}
