import InlineKit
import InlineUI
import SwiftUI
import UIKit

struct ChatRowView: View {
  let item: HomeChatItem
  var type: ChatType {
    item.chat?.type ?? .privateChat
  }

  private func formatDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    let components = calendar.dateComponents([.second], from: date, to: now)

    if let seconds = components.second, seconds < 60 {
      return "now"
    } else if calendar.isDateInToday(date) {
      let formatter = DateFormatter()
      formatter.dateFormat = "h:mm a"
      formatter.amSymbol = ""
      return formatter.string(from: date).replacingOccurrences(of: " PM", with: "PM")
    } else {
      let formatter = DateFormatter()
      formatter.dateFormat = "MMM d, h:mm"
      return formatter.string(from: date)
    }
  }

  var body: some View {
    HStack(alignment: .top) {
      UserAvatar(user: item.user, size: 36)
        .padding(.trailing, 6)
        .overlay(alignment: .bottomTrailing) {
          Circle()
            .fill(.green)
            .frame(width: 12, height: 12)
            .padding(.leading, -14)
        }
      VStack(alignment: .leading) {
        HStack {
          Text(type == .privateChat ? item.user.firstName ?? "" : item.chat?.title ?? "")
            .fontWeight(.medium)
            .foregroundColor(.primary)
          Spacer()
          Text(formatDate(item.message?.date ?? Date()))
            .font(.callout)
            .foregroundColor(.secondary)
        }

        if let text = item.message?.text {
          Text(text.replacingOccurrences(of: "\n", with: " "))
            .font(.callout)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

        } else {
          Text("No messages yet")
            .font(.callout)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
    }
    .frame(height: 48)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

#Preview("ChatRowView") {
  VStack(spacing: 12) {
    // Private chat example
    let privateDialog = Dialog(optimisticForUserId: 2)

    let privateUser = User(
      id: 2,
      email: "john@example.com",
      firstName: "Dena",
      lastName: "Doe"
    )

    let privateChat = Chat(
      id: 1,
      date: Date(),
      type: .privateChat,
      title: "John Doe",
      spaceId: nil,
      peerUserId: 2,
      lastMsgId: nil
    )

    ChatRowView(
      item: HomeChatItem(
        dialog: privateDialog, user: privateUser, chat: privateChat,
        message: Message(
          messageId: 1,
          fromId: 2,
          date: Date(),
          text: "فارسی هم ساپورت میکنه به به",
          peerUserId: 2,
          peerThreadId: nil,
          chatId: 1
        )
      )
      // item: HomeChatItem(
      //   dialog: privateDialog,
      //   user: privateUser,
      //   chat: privateChat,
      // message:
      // )
    )
    .padding()
  }
}
