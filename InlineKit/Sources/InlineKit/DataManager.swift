import Foundation
import GRDB

enum DataManagerError: Error {
    case networkError
    case apiError(description: String, code: Int)
    case localSaveError
    case notAuthorized
}

// ?? should we use main actor here?

/// Query or mutate data on the server and update local database
@MainActor
public class DataManager: ObservableObject {
    private var database: AppDatabase
    private var log = Log.scoped("DataManager")

    public init(database: AppDatabase) {
        self.database = database
    }

    public static let shared = DataManager(database: AppDatabase.shared)

    public func fetchMe() async throws -> User {
        log.debug("fetchMe")
        do {
            let result = try await ApiClient.shared.getMe()
            print("fetchMe result: \(result)")
            let user = User(from: result.user)
            try await database.dbWriter.write { db in
                try user.save(db)
                print("User saved: \(user)")
            }
            print("currentUserId: \(Auth.shared.getCurrentUserId() ?? Int64.min)")
            return user
        } catch {
            Log.shared.error("Error fetching user", error: error)
            throw error
        }
    }

    public func createSpace(name: String) async throws -> Space {
        log.debug("createSpace")
        do {
            let result = try await ApiClient.shared.createSpace(name: name)
            print("Create space result: \(result)")
            let space = Space(from: result.space)
            try await database.dbWriter.write { db in
                try space.save(db)

                let member = Member(from: result.member)
                try member.save(db)

                // Create main thread (default)
                for chat in result.chats {
                    let thread = Chat(from: chat)
                    try thread.save(db)
                }
            }

            // Return for navigating to space using id
            return space
        } catch {
            Log.shared.error("Failed to create space", error: error)
            throw error
        }
    }

    public func createThread(spaceId: Int64, title: String?) async throws -> Int64? {
        log.debug("createThread")
        do {
            return try await database.dbWriter.write { db in

                // TODO: API call to create thread

                // Create the chat
                let thread = Chat(
                    date: Date.now,
                    type: .thread,
                    title: title,
                    spaceId: spaceId
                )
                try thread.save(db)

                return thread.id
            }
        } catch {
            Log.shared.error("Failed to create thread", error: error)
            throw error
        }
    }

    public func createPrivateChat(peerId: Int64) async throws -> Int64? {
        log.debug("createPrivateChat")
        do {
            let result = try await ApiClient.shared.createPrivateChat(peerId: peerId)

            try await database.dbWriter.write { db in
                let chat = Chat(from: result.chat)
                try chat.save(db)
            }

            return result.chat.id
        } catch {
            Log.shared.error("Failed to create private chat", error: error)
        }
        return nil
    }

    /// Get list of user spaces and saves them
    @discardableResult
    public func getSpaces() async throws -> [Space] {
        log.debug("getSpaces")
        do {
            let result = try await ApiClient.shared.getSpaces()

            let spaces = try await database.dbWriter.write { db in
                let spaces = result.spaces.map { space in
                    Space(from: space)
                }
                try spaces.forEach { space in
                    try space.save(db)
                }
                for member in result.members {
                    let member = Member(from: member)
                    try member.save(db)
                }
                return spaces
            }

            return spaces
        } catch {
            throw error
        }
    }

    public func sendMessage(peerId: Peer, text: String) async throws {
        log.debug("sendMessage")
        try await database.dbWriter.write { db in
            let message = Message(
                fromId: Auth.shared.getCurrentUserId()!,
                date: Date.now,
                text: text,
                peerUserId: peerId.isPrivate ? peerId.id : nil,
                peerThreadId: peerId.isThread ? peerId.id : nil,
                out: true
            )
            try message.save(db)
        }
        // TODO: Trigger remote call
    }

    public func deleteSpace(spaceId: Int64) async throws {
        log.debug("deleteSpace")
        do {
            //            Use for user ID
            //            guard let currentUserId = Auth.shared.getCurrentUserId() else {
            //                throw DataManagerError.notAuthorized
            //            }

            let _ = try await ApiClient.shared.deleteSpace(spaceId: spaceId)

            try await database.dbWriter.write { db in
                try Space.deleteOne(db, id: spaceId)

                try Member
                    .filter(Column("spaceId") == spaceId)
                    .deleteAll(db)

                try Chat
                    .filter(Column("spaceId") == spaceId)
                    .deleteAll(db)
            }
        } catch {
            Log.shared.error("Failed to delete space", error: error)
            throw error
        }
    }

    public func leaveSpace(spaceId: Int64) async throws {
        log.debug("leaveSpace")
        do {
            let _ = try await ApiClient.shared.leaveSpace(spaceId: spaceId)

            try await database.dbWriter.write { db in
                try Space.deleteOne(db, id: spaceId)

                try Member
                    .filter(Column("spaceId") == spaceId)
                    .deleteAll(db)

                try Chat
                    .filter(Column("spaceId") == spaceId)
                    .deleteAll(db)
            }
        } catch {
            Log.shared.error("Failed to leave space", error: error)
            throw error
        }
    }

    @discardableResult
    public func getPrivateChats() async throws -> [Chat] {
        log.debug("getPrivateChats")
        do {
            let result = try await ApiClient.shared.getPrivateChats()

            let chats = try await database.dbWriter.write { db in
                let chats = result.chats.map { chat in
                    Chat(from: chat)
                }
                print("getPrivateChats chats: \(chats)")
                try chats.forEach { chat in
                    try chat.save(db)
                }

                return chats
            }

            print("getPrivateChats result: \(chats)")
            return chats
        } catch {
            throw error
        }
    }
    //    public func getFullSpace(spaceId: Int64) async throws -> Space {
    ////        log.debug("getFullSpace")
    ////        do {
    ////            let result = try await ApiClient.shared.getFullSpace(spaceId: spaceId)
    ////            let space = Space(from: result.space)
    ////            try await database.dbWriter.write { db in
    ////                try space.save(db)
    ////                for member in result.members {
    ////                    let member = Member(from: member)
    ////                    try member.save(db)
    ////                }
    ////            }
    ////        } catch {
    ////            Log.shared.error("Failed to get full space", error: error)
    ////            throw error
    ////        }
    //    }
}
