import AppKit
import InlineKit
import SwiftUI

class ChatViewAppKit: NSView {
  var peerId: Peer
  
  private lazy var messageList: MessageListAppKit = {
    let messageList = MessageListAppKit(peerId: peerId)

    return messageList
  }()
  
  private lazy var compose: ComposeAppKit = {
    let compose = ComposeAppKit(peerId: self.peerId, messageList: messageList)

    return compose
  }()
  
  init(peerId: Peer) {
    self.peerId = peerId
    super.init(frame: .zero)
    setupView()
  }
  
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private var composeView: NSView {
    compose
  }
  
  private var messageListView: NSView {
    messageList.view
  }
  
  private func setupView() {
    // Enable Auto Layout for the main view
    translatesAutoresizingMaskIntoConstraints = false
    messageListView.translatesAutoresizingMaskIntoConstraints = false
    composeView.translatesAutoresizingMaskIntoConstraints = false
    
    addSubview(messageListView)
    addSubview(composeView)
    
    NSLayoutConstraint.activate([
      // messageList
      messageListView.topAnchor.constraint(equalTo: topAnchor),
      messageListView.leadingAnchor.constraint(equalTo: leadingAnchor),
      messageListView.trailingAnchor.constraint(equalTo: trailingAnchor),
      messageListView.bottomAnchor.constraint(equalTo: bottomAnchor),
      
      // compose
      composeView.bottomAnchor.constraint(equalTo: bottomAnchor),
      composeView.leadingAnchor.constraint(equalTo: leadingAnchor),
      composeView.trailingAnchor.constraint(equalTo: trailingAnchor),
      
      // Vertical stack
//      composeView.topAnchor.constraint(equalTo: messageListView.bottomAnchor),
    ])
  }
  
  func update(messages: [FullMessage]) {}
  
  func update(viewModel: FullChatViewModel) {
    // Update compose
    compose.update(viewModel: viewModel)
  }
}
