import Foundation
import GRDB

public struct ApiPhoto: Codable, Hashable, Sendable {
  public var fileUniqueId: String
  public var width: Int
  public var height: Int
  public var fileSize: Int
  public var mimeType: String? // for now optional
  public var temporaryUrl: String
}

public enum MessageFileType: String, Codable, DatabaseValueConvertible, Sendable {
  case photo
  case file
  case video
}

public struct File: FetchableRecord, Identifiable, Codable, Hashable, PersistableRecord,
  TableRecord,
  Sendable, Equatable
{
  // Locally autoincremented id
  public var id: String

  // Raw message text from server
  public var fileUniqueId: String?

  // File type
  public var fileType: MessageFileType

  // File name with extension
  public var fileName: String? // optional bc added later

  // Mime Type
  public var mimeType: String? // optional bc added later

  // Is uploading?
  public var uploading: Bool

  // File size
  public var fileSize: Int64

  // URL
  public var temporaryUrl: String?
  public var temporaryUrlExpiresAt: Date?

  public var width: Int?
  public var height: Int?

  // Local path
  public var localPath: String?

  // For a message
//  public var messageLocalId: Int64?
//  public static let message = belongsTo(
//    Message.self,
//    using: ForeignKey(["messageLocalId"], to: ["id"])
//  )

  // For a profile photo
  public var profileForUserId: Int64?
  public static let profileForUser = belongsTo(
    User.self,
    using: ForeignKey(["profileForUserId"], to: ["id"])
  )

  public init(
    id: String,
    fileUniqueId: String?,
    fileType: MessageFileType,
    fileName: String,
    uploading: Bool,
    fileSize: Int64,
    temporaryUrl: String?,
    temporaryUrlExpiresAt: Date?,
    width: Int?,
    height: Int?,
    localPath: String?,
    mimeType: String?
  ) {
    self.id = id
    self.fileUniqueId = fileUniqueId
    self.fileType = fileType
    self.fileName = fileName
    self.uploading = uploading
    self.fileSize = fileSize
    self.temporaryUrl = temporaryUrl
    self.temporaryUrlExpiresAt = temporaryUrlExpiresAt
    self.width = width
    self.height = height
    self.localPath = localPath
    self.mimeType = mimeType
  }

  public init(fromAttachment attachment: SendMessageAttachment) {
    id = attachment.id
    uploading = true
    fileSize = attachment.fileSize
    localPath = attachment.filePath
    switch attachment.type {
      case let .photo(format, width, height):
        fileName = "\(id)\(format.toExt())"
        mimeType = format.toMimeType()
        self.width = width
        self.height = height
        fileType = .photo
      default:
        fileName = "\(id).file" // DA DUCK .file TODO: change this
        fileType = .file // for now until we support more
    }

    // waiting for remote response to fill out
    fileUniqueId = nil
    temporaryUrl = nil
    temporaryUrlExpiresAt = nil
  }
}

public extension File {
  init(fromPhoto photo: ApiPhoto) throws {
    guard URL(string: photo.temporaryUrl) != nil else {
      throw FileError.invalidTemporaryUrl
    }

    id = UUID().uuidString
    fileUniqueId = photo.fileUniqueId
    fileType = .photo
    uploading = false
    fileSize = Int64(photo.fileSize)
    temporaryUrl = photo.temporaryUrl
    temporaryUrlExpiresAt = Calendar.current.date(byAdding: .day, value: 7, to: .now)
    width = photo.width
    height = photo.height
    localPath = nil

    let ext =
      switch photo.mimeType {
        case "image/jpeg":
          ".jpg"
        case "image/png":
          ".png"
        default:
          ".jpg"
      }

    mimeType = photo.mimeType
    fileName = "\(id)\(ext)"
  }
}

public extension File {
  /// Returns the file local ID
  static func save(
    _ db: Database,
    apiPhoto photo: ApiPhoto,
    forMessageLocalId: Int64? = nil,
    forUserId: Int64? = nil
  ) throws -> File {
    // fetch
    guard
      var existing =
      try File
        .filter(Column("fileUniqueId") == photo.fileUniqueId)
        .fetchOne(db)
    else {
      // ... create new
      var file = try File(fromPhoto: photo)
      
      print("saving file \(file)")

      // associate
      if let forMessageLocalId {
        //file.messageLocalId = forMessageLocalId
      } else if let forUserId {
        file.profileForUserId = forUserId
      }

      // insert
      return try file.insertAndFetch(db)
    }

    // update
    existing.temporaryUrl = photo.temporaryUrl
    existing.temporaryUrlExpiresAt = Calendar.current.date(byAdding: .day, value: 7, to: .now)

    existing.uploading = false
    existing.fileSize = Int64(photo.fileSize)
    existing.width = photo.width
    existing.height = photo.height

    // associate
    if let forMessageLocalId {
      //existing.messageLocalId = forMessageLocalId
    } else if let forUserId {
      existing.profileForUserId = forUserId
    }

    return try existing.updateAndFetch(db)
  }
}

// Add this error enum
public enum FileError: Error {
  case invalidTemporaryUrl
}

// Helpers
public extension File {
  func getLocalURL() -> URL? {
    guard let localPath else {
      return nil
    }
    return
      FileHelpers
        .getDocumentsDirectory()
        .appending(path: localPath)
  }

  func getRemoteURL() -> URL? {
    guard let temporaryUrl else {
      return nil
    }
    return URL(string: temporaryUrl)
  }
}
