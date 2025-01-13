import InlineKit
import SwiftUI
import UIKit

class UIMessageView: UIView {
  // MARK: - Properties

  private var interaction: UIContextMenuInteraction?

  private lazy var messageLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.backgroundColor = .clear
    label.textAlignment = .natural
    label.font = .systemFont(ofSize: 17)
    label.textColor = textColor
    label.numberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    return label
  }()

  private let bubbleView: UIView = {
    let view = UIView()
    view.layer.cornerRadius = 19
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  var fullMessage: FullMessage

  var outgoing: Bool {
    fullMessage.message.out == true
  }

  private var bubbleColor: UIColor {
    outgoing ? ColorManager.shared.selectedColor : UIColor.systemGray5.withAlphaComponent(0.4)
  }

  private var textColor: UIColor {
    outgoing ? .white : .label
  }

  private var message: Message {
    fullMessage.message
  }

  private let metadataView: MessageMetadata

  private var multiline: Bool {
    guard let text = message.text else { return false }
    return text.count > 24 || text.contains("\n")
  }

  private var labelVerticalPadding: CGFloat = 9.0
  private var labelHorizantalPadding: CGFloat = 12.0

  // MARK: - Initialization

  init(fullMessage: FullMessage) {
    self.fullMessage = fullMessage
    self.metadataView = MessageMetadata(fullMessage)
    metadataView.translatesAutoresizingMaskIntoConstraints = false
    super.init(frame: .zero)

    setupViews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup

  private func setupViews() {
    addSubview(bubbleView)
    bubbleView.addSubview(messageLabel)
    bubbleView.addSubview(metadataView)

    setupAppearance()
    setupConstraints()
//    setupContextMenu()
  }

  private func setupConstraints() {
    let messageConstraints =
      multiline ? setupMultilineMessageConstraints() : setupOneLineMessageConstraints()

    NSLayoutConstraint.activate(
      [
        // Bubble view constraints
        bubbleView.topAnchor.constraint(equalTo: topAnchor),
        bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),
        bubbleView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9),
      ] + messageConstraints)

    if outgoing {
      bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
    } else {
      bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
    }
  }

  private func setupMultilineMessageConstraints() -> [NSLayoutConstraint] {
    return [
      messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: labelVerticalPadding),
      messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: labelHorizantalPadding),
      messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -labelHorizantalPadding),
      messageLabel.bottomAnchor.constraint(equalTo: metadataView.topAnchor, constant: -labelVerticalPadding),

      metadataView.leadingAnchor.constraint(
        greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 14),
      metadataView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
      metadataView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -14),
    ]
  }

  private func setupOneLineMessageConstraints() -> [NSLayoutConstraint] {
    return [
      messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: labelVerticalPadding),
      messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: labelHorizantalPadding),
      messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -labelVerticalPadding),

      metadataView.leadingAnchor.constraint(equalTo: messageLabel.trailingAnchor, constant: 8),
      metadataView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
      metadataView.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
    ]
  }

  private func setupAppearance() {
    let attributedString = NSMutableAttributedString(
      string: message.text ?? "",
      attributes: [
        .font: UIFont.systemFont(ofSize: 17),
        .foregroundColor: textColor,
      ])

    messageLabel.attributedText = attributedString
    messageLabel.textColor = textColor
    bubbleView.backgroundColor = bubbleColor
  }

  private func setupContextMenu() {
    let interaction = UIContextMenuInteraction(delegate: self)
    self.interaction = interaction
    bubbleView.addInteraction(interaction)
  }
}

// MARK: - Context Menu

extension UIMessageView: UIContextMenuInteractionDelegate {
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration?
  {
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      guard let self else { return nil }

      let copyAction = UIAction(title: "Copy") { _ in
        UIPasteboard.general.string = self.message.text
      }

      return UIMenu(children: [copyAction])
    }
  }
}
