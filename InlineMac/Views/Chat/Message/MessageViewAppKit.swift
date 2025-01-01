// MessageView.swift
import AppKit
import InlineKit
import InlineUI
import SwiftUI

class MessageViewAppKit: NSView {
  static let avatarSize: CGFloat = Theme.messageAvatarSize
  private var fullMessage: FullMessage
  private var props: MessageViewProps
  private var from: User {
    fullMessage.user ?? User.deletedInstance
  }

  private var showsAvatar: Bool { props.firstInGroup }
  private var showsName: Bool { props.firstInGroup }
  private var message: Message {
    fullMessage.message
  }

  private var outgoing: Bool {
    message.out == true
  }

  private var hasBubble: Bool {
    Theme.messageIsBubble
  }

  private var textWidth: CGFloat {
    if hasBubble {
      max(Theme.messageBubbleMinWidth, props.textWidth ?? 100.0)
    } else {
      props.textWidth ?? 100.0
    }
  }

  // MARK: Views

  private var bubbleColor: NSColor {
    outgoing ? Theme.messageBubbleOutgoingColor : Theme.messageBubbleColor
  }

  private var textColor: NSColor {
    if hasBubble {
      outgoing ? NSColor.white : NSColor.labelColor
    } else {
      NSColor.labelColor
    }
  }

  private var linkColor: NSColor {
    if hasBubble {
      outgoing ? NSColor.white : NSColor.linkColor
    } else {
      NSColor.linkColor
    }
  }

  private var senderFont: NSFont {
    if hasBubble {
      .systemFont(
        ofSize: NSFont.smallSystemFontSize,
        weight: .medium
      )
    } else {
      .systemFont(
        ofSize: NSFont.systemFontSize,
        weight: .semibold
      )
    }
  }

  private lazy var bubbleView: BasicView = {
    let view = BasicView()
    view.wantsLayer = true
    view.backgroundColor = bubbleColor
    view.layer?.cornerRadius = Theme.messageBubbleRadius
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var avatarView: UserAvatarView = {
    let view = UserAvatarView(user: self.from)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var nameLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = senderFont
    label.lineBreakMode = .byTruncatingTail

    return label
  }()

  private lazy var textView: NSTextView = {
    let textView = MessageTextView(usingTextLayoutManager: true) // Experimental text kit 2

    // Not sure if this helps actually
//     textView.wantsLayer = true

    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    // In some international languages the measurements might be off slightly, this could avoid cutting off text in that case
    textView.clipsToBounds = false
    textView.textContainerInset = MessageTextConfiguration.containerInset
    textView.font = MessageTextConfiguration.font
    textView.textColor = textColor

    let textContainer = textView.textContainer
    textContainer?.widthTracksTextView = true
    textContainer?.heightTracksTextView = true
//    textView.isVerticallyResizable = true
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = false

    textView.delegate = self

    // In NSTextView you need to customize link colors here otherwise the attributed string for links
    // does not have any effect.
    textView.linkTextAttributes = [
      .foregroundColor: linkColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .cursor: NSCursor.pointingHand
    ]

    // Match the sizes and spacing with the size calculator we use to calculate cell height
    MessageTextConfiguration.configureTextContainer(textContainer!)
    MessageTextConfiguration.configureTextView(textView)

    return textView
  }()

  func reflectBoundsChange(fraction: CGFloat) {
    // TODO: update color reflecting the scroll
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window != nil {
      // Register for scroll visibility notifications
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleBoundsChange),
        name: NSView.boundsDidChangeNotification,
        object: enclosingScrollView?.contentView
      )
    }
  }

  // Fix a bug that when messages were out of viewport and came back during a live resize
  // text would not appear until the user ended live resize operation. Seems like in TextKit 2 calling layoutViewport solves this.
  // The property `allowsNonContiguousLayout` also seems to fix this issue but it has two other issues:
  // 1. that forces textkit 1
  // 2. it adds a scroll jump everytime user resizes the window
  // which made it unsusable.
  // This approach still needs further testing.
  @objc private func handleBoundsChange(_ notification: Notification) {
    guard let scrollView = enclosingScrollView,
          let clipView = notification.object as? NSClipView else { return }

    let visibleRect = scrollView.documentVisibleRect
    let frameInClipView = convert(bounds, to: clipView)

    if visibleRect
      // Limit the layout to the top 30 points of viewport so we minimize number of messages that are layouted
      // TODO: we need to eventually find a more optimized version of this
      .divided(atDistance: 30.0, from: .minYEdge).slice
      .intersects(frameInClipView)
    {
      // Only do this during live resize
      if !textView.inLiveResize {
        return
      }

      // TextKit 2 specific configuration
      if let textLayoutManager = textView.textLayoutManager {
        Log.shared.debug("Layouting viewport for text view \(message.id)")

        DispatchQueue.main.async {
          // Enable continuous layout
          textLayoutManager.textViewportLayoutController.layoutViewport()
        }
      }
    }
  }

  func ensureLayout(_ props: MessageViewProps) {
    self.props = props

    textViewWidthConstraint.constant = props.textWidth ?? 0
    textViewHeightConstraint.constant = props.textHeight ?? 0

    setupMessageText()
  }

  // MARK: - Initialization

  init(fullMessage: FullMessage, props: MessageViewProps) {
    self.fullMessage = fullMessage
    self.props = props
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func setupView() {
    if hasBubble {
      addSubview(bubbleView)
    }

    if showsAvatar {
      addSubview(avatarView)
    }

    if showsName {
      addSubview(nameLabel)
      let name = from.firstName ?? from.username ?? ""
      nameLabel.stringValue = outgoing ? "You" : name

      if hasBubble {
        nameLabel.textColor = NSColor.lightGray
      } else {
        nameLabel.textColor = NSColor(
          InitialsCircle.ColorPalette
            .color(for: name)
            .adjustLuminosity(by: -0.08) // TODO: Optimize
        )
      }
    }

    addSubview(textView)

    setupMessageText()
    setupConstraints()
    setupContextMenu()
  }

  private var textViewWidthConstraint: NSLayoutConstraint!
  private var textViewHeightConstraint: NSLayoutConstraint!

  private func setupConstraints() {
    // var topSpacing = props.isFirstMessage ? Theme.messageListTopInset : 0.0
    // let bottomSpacing = props.isLastMessage ? Theme.messageListBottomInset : 0.0

    var topPadding = Theme.messageVerticalPadding
    let bottomPadding = Theme.messageVerticalPadding
    let nameAndContentGap = Theme.messageVerticalStackSpacing
    let bgPadding = 0.0
    let bubblePadding = Theme.messageBubblePadding
    let avatarLeading = Theme.messageSidePadding
    let contentLeading = avatarLeading + Self.avatarSize + Theme.messageHorizontalStackSpacing - bgPadding
    let sidePadding = Theme.messageSidePadding - bgPadding
    let senderNameLeadingPadding = hasBubble ? 6.0 : 0.0
    let bubblePaddingVertical = hasBubble ? bubblePadding.height : 0.0
    let bubblePaddingHorizontal = hasBubble ? bubblePadding.width : 0.0

    if props.firstInGroup {
      topPadding += Theme.messageGroupSpacing
    }

    if showsAvatar {
      NSLayoutConstraint.activate([
        avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: avatarLeading),
        avatarView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
        avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
        avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSize)
      ])
    }

    if showsName {
      NSLayoutConstraint.activate([
        nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentLeading + senderNameLeadingPadding),
        nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
        nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -sidePadding),
        nameLabel.heightAnchor
          .constraint(equalToConstant: Theme.messageNameLabelHeight)
      ])
    }

//    let textViewSideConstraint = props.isRtl ?
//      textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sidePadding) :
//      textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentLeading)

//    let textViewSideConstraint = outgoing ?
//      textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sidePadding) :
//      textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentLeading + bubblePaddingHorizontal)

    let textViewSideConstraint =
      textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentLeading + bubblePaddingHorizontal)

    textViewWidthConstraint = textView.widthAnchor.constraint(equalToConstant: textWidth)
    textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: props.textHeight ?? 0)

    NSLayoutConstraint.activate(
      [
        // Text view
        textView.topAnchor.constraint(
          equalTo: showsName ? nameLabel.bottomAnchor : topAnchor,
          constant: showsName ? nameAndContentGap + bubblePaddingVertical : topPadding + bubblePaddingVertical
        ),
        textViewWidthConstraint,
        textViewHeightConstraint,
        textViewSideConstraint
      ]
    )

    if hasBubble {
      NSLayoutConstraint.activate(
        [
          // Bubble view
          bubbleView.topAnchor.constraint(equalTo: textView.topAnchor, constant: -bubblePadding.height),
          bubbleView.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: -bubblePadding.width),
          bubbleView.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: bubblePadding.width),
          bubbleView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: bubblePadding.height)
        ]
      )
    }
  }

  private func setupMessageText() {
    let text = message.text ?? ""

    textView.baseWritingDirection = props.isRtl ? .rightToLeft : .natural

    let key = "\(text)___\(message.stableId)" // consider a hash here. // note: need to add ID otherwise messages with same text will be overriding each other styles
    if let attrs = CacheAttrs.shared.get(key: key) {
      textView.textStorage?.setAttributedString(attrs)

//      if let textLayoutManager = textView.textLayoutManager {
//        textLayoutManager
//          .ensureLayout(for: textLayoutManager.documentRange)
//      }

      return
    }

    // Create mutable attributed string
    let attributedString = NSMutableAttributedString(
      // Trim to avoid known issue with size calculator
      string: text.trimmingCharacters(in: .whitespacesAndNewlines),
      attributes: [
        .font: MessageTextConfiguration.font,
        .foregroundColor: textColor
      ]
    )

    // Detect and add links
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    if let detector = detector {
      let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

      for match in matches {
        if let url = match.url {
          attributedString.addAttributes([
            .cursor: NSCursor.pointingHand,
            .link: url,
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
          ], range: match.range)
        }
      }
    }

    textView.textStorage?.setAttributedString(attributedString)
//    if let textLayoutManager = textView.textLayoutManager {
//      textLayoutManager
//        .ensureLayout(for: textLayoutManager.documentRange)
//    }

    CacheAttrs.shared.set(key: key, value: attributedString)
  }

  private func setupContextMenu() {
    let menu = NSMenu()

    let idItem = NSMenuItem(title: "ID: \(message.id)", action: nil, keyEquivalent: "")
    idItem.isEnabled = false
    menu.addItem(idItem)

    let copyItem = NSMenuItem(title: "Copy", action: #selector(copyMessage), keyEquivalent: "c")
    menu.addItem(copyItem)

    menu.delegate = self
    self.menu = menu
  }

  override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
    if hasBubble {
      bubbleView.backgroundColor = bubbleColor
        .highlight(withLevel: 0.3)
    } else {
      // Apply selection style when menu is about to open
      layer?.backgroundColor = NSColor.darkGray
        .withAlphaComponent(0.1).cgColor
    }
  }

  override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
    if hasBubble {
      bubbleView.backgroundColor = bubbleColor
    } else {
      // Remove selection style when menu closes
      layer?.backgroundColor = nil
    }
  }

  // MARK: - Actions

  @objc private func copyMessage() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(message.text ?? "", forType: .string)
  }
}

extension MessageViewAppKit: NSTextViewDelegate {}
extension MessageViewAppKit: NSMenuDelegate {}

struct MessageViewProps: Equatable, Codable, Hashable {
  /// Used to show sender and photo
  var firstInGroup: Bool
  var isLastMessage: Bool
  var isFirstMessage: Bool
  var isRtl: Bool

  var textWidth: CGFloat?
  var textHeight: CGFloat?

  /// Used in cache key
  func toString() -> String {
    "\(firstInGroup ? "FG" : "")\(isLastMessage == true ? "LM" : "")\(isFirstMessage == true ? "FM" : "")\(isRtl ? "RTL" : "")"
  }

  func equalExceptSize(_ rhs: MessageViewProps) -> Bool {
    firstInGroup == rhs.firstInGroup &&
      isLastMessage == rhs.isLastMessage &&
      isFirstMessage == rhs.isFirstMessage &&
      isRtl == rhs.isRtl
  }
}

// Helper extension for constraint priorities
private extension NSLayoutConstraint {
  func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
    self.priority = priority
    return self
  }
}
