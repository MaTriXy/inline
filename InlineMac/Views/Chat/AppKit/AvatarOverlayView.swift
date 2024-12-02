import AppKit
import InlineKit
import SwiftUI

class AvatarOverlayView: NSView {
  var avatarViews: [Int: UserAvatarView] = [:]
  static let size: CGFloat = Theme.messageAvatarSize
  private let topPadding: CGFloat = Theme.messageVerticalPadding
  private let topEdgeInset: CGFloat = Theme.messageListTopInset
  
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    clipsToBounds = true
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func updateAvatar(for row: Int, user: User, yOffset: CGFloat, animated: Bool = true) {
    let avatarView = avatarViews[row] ?? createAvatarView(for: user)
    avatarViews[row] = avatarView
    
    let frame = NSRect(
      x: 0,
      y: yOffset,
      width: Self.size,
      height: Self.size
    )
    
    avatarView.frame = frame
  }
  
  private func createAvatarView(for user: User) -> UserAvatarView {
    let avatarView = UserAvatarView(frame: .zero)
    avatarView.wantsLayer = true
    avatarView.layer?.zPosition = 100
    avatarView.user = user
    addSubview(avatarView)
    return avatarView
  }
  
  func removeAvatar(for row: Int) {
    avatarViews[row]?.removeFromSuperview()
    avatarViews.removeValue(forKey: row)
  }
  
  func clearAvatars() {
    avatarViews.values.forEach { $0.removeFromSuperview() }
    avatarViews.removeAll()
  }
}

class MessageAvatarView: NSView {
  static let size: CGFloat = Theme.messageAvatarSize
  
  private lazy var avatarView: UserAvatarView = {
    let view = UserAvatarView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
//    view.clipsToBounds = false
    view.wantsLayer = true
//    view.layer?.zPosition = 100
    return view
  }()
  
  private var topConstraint: NSLayoutConstraint?
  
  init() {
    super.init(frame: .zero)
    setupView()
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func setupView() {
    wantsLayer = true
    
    addSubview(avatarView)
    
    NSLayoutConstraint.activate([
      avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
      avatarView.widthAnchor.constraint(equalToConstant: Self.size),
      avatarView.heightAnchor.constraint(equalToConstant: Self.size)
    ])
    
    topConstraint = avatarView.topAnchor.constraint(equalTo: topAnchor)
    topConstraint?.isActive = true
  }
  
  func configure(with user: User) {
    avatarView.user = user
  }
}
