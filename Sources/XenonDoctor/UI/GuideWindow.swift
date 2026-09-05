import AppKit

/// The Stratos Xenon guide as formatted text: section headings, short bullets, button
/// names in bold, and three kinds of callout (do this, careful, why). Every line was
/// confirmed on the owner's pads or comes from the Cosmic Byte manual; nothing invented.
/// Shown in the Guide tab of the main window; this type only builds the text and the view.
enum GuideWindow {
    private enum Block {
        case h1(String)
        case h2(String)
        case p(String)
        case bullet(String)
        case doThis(String)
        case careful(String)
        case why(String)
        case link(String, String)
    }

    /// `**text**` marks a button name or key phrase, rendered bold in the accent color.
    private static let blocks: [Block] = [
        .h1("Stratos Xenon guide"),
        .p("Two pads, one Mac, one game. This page is everything you need when a pad misbehaves."),
        .link("github.com/alcatraz627/xenon-doctor", "https://github.com/alcatraz627/xenon-doctor"),

        .h2("Which pad is which"),
        .bullet("**SQUARE** pencil mark: Aakarsh's pad. Bluetooth address D0:27:96:F5:49:AD."),
        .bullet("**CIRCLE** pencil mark: the other pad. Bluetooth address D0:27:96:D0:11:6D."),
        .bullet("The Mac shows a pad under the name it was given when first paired."),

        .h2("Everyday"),
        .doThis("Turn on: press **PS** once. The light bar blinks, then goes solid within five seconds."),
        .doThis("Turn off: hold **PS** for about ten seconds until the light bar goes dark. Do this after closing the game."),
        .bullet("Launch Stardew Valley from Steam as usual. The game reads the pad directly."),

        .h2("Pad blinks, shows connected, then drops"),
        .doThis("Hold **Share** and **PS** together for about four seconds until the light bar blinks fast, then let go. It connects and stays."),
        .bullet("You do not need to forget the pad in Bluetooth settings."),
        .why("After a crash or a forced restart the Mac loses the pad's service record, and the pad only hands it out while in pairing mode."),

        .h2("Two rules that keep it working"),
        .careful("Never use Steam's **Stop** button on a game. Quit the game from its own menu. The one time this Mac froze, Stop had just been used with a pad connected."),
        .careful("Xenon Doctor keeps Steam away from the pad. If the Steam row ever says Steam has taken over, click **Restart Steam** and nothing else."),

        .h2("Pairing a pad to a new Mac"),
        .doThis("Open System Settings, Bluetooth. Hold **Share** and **PS** on the pad until the light bar blinks fast. Click **Connect** next to the pad when it appears."),
        .bullet("Pair the second pad the same way. Both can stay paired."),

        .h2("Modes"),
        .bullet("The pad has several modes. On a Mac it must be in PS4 mode, which is what it uses when paired as above."),
        .bullet("**Share** and **Options** held together for two seconds switches X-input and D-input. If the pad ever acts strangely, turn it off and on, then re-pair with **Share** and **PS**."),

        .h2("If nothing works"),
        .bullet("Charge the pad with its USB-C cable for half an hour, then try **Share** and **PS** again. A flat pad blinks and never connects."),
        .bullet("Open the **Button tester** tab. If buttons light there, the pad reaches the Mac and the problem is in Steam or the game."),
    ]

    static func attributed() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let bold = NSFont.systemFont(ofSize: 13, weight: .semibold)

        func para(spacingBefore: CGFloat, spacingAfter: CGFloat, indent: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = spacingBefore
            p.paragraphSpacing = spacingAfter
            p.firstLineHeadIndent = indent
            p.headIndent = indent + 16
            p.lineSpacing = 2
            return p
        }

        func inline(_ text: String, color: NSColor, font: NSFont = body) -> NSAttributedString {
            let s = NSMutableAttributedString()
            let parts = text.components(separatedBy: "**")
            for (i, part) in parts.enumerated() {
                let strong = i % 2 == 1
                s.append(NSAttributedString(string: part, attributes: [
                    .font: strong ? bold : font,
                    .foregroundColor: strong ? NSColor.controlAccentColor : color,
                ]))
            }
            return s
        }

        func line(_ prefix: String, _ prefixColor: NSColor, _ text: String, _ color: NSColor, style: NSParagraphStyle) {
            let s = NSMutableAttributedString(string: prefix, attributes: [.font: bold, .foregroundColor: prefixColor])
            s.append(inline(text, color: color))
            s.append(NSAttributedString(string: "\n"))
            s.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: s.length))
            out.append(s)
        }

        for b in blocks {
            switch b {
            case .h1(let t):
                let s = NSMutableAttributedString(string: t + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: para(spacingBefore: 0, spacingAfter: 4),
                ])
                out.append(s)
            case .h2(let t):
                let s = NSMutableAttributedString(string: t.uppercased() + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .kern: 1.2,
                    .paragraphStyle: para(spacingBefore: 18, spacingAfter: 6),
                ])
                out.append(s)
            case .p(let t):
                line("", .clear, t, .secondaryLabelColor, style: para(spacingBefore: 0, spacingAfter: 6))
            case .link(let text, let url):
                let s = NSMutableAttributedString(string: text + "\n", attributes: [
                    .font: body,
                    .foregroundColor: NSColor.linkColor,
                    .link: URL(string: url) as Any,
                    .paragraphStyle: para(spacingBefore: 0, spacingAfter: 6),
                ])
                out.append(s)
            case .bullet(let t):
                line("•  ", .tertiaryLabelColor, t, .labelColor, style: para(spacingBefore: 0, spacingAfter: 4, indent: 8))
            case .doThis(let t):
                line("▶  ", .systemGreen, t, .labelColor, style: para(spacingBefore: 0, spacingAfter: 4, indent: 8))
            case .careful(let t):
                line("!  ", .systemOrange, t, .labelColor, style: para(spacingBefore: 0, spacingAfter: 4, indent: 8))
            case .why(let t):
                line("why  ", .tertiaryLabelColor, t, .secondaryLabelColor, style: para(spacingBefore: 0, spacingAfter: 4, indent: 8))
            }
        }
        return out
    }

    /// The guide as a scrolling text view, ready to sit in the window's Guide tab.
    static func scrollView() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 680))
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .windowBackgroundColor
        tv.textContainerInset = NSSize(width: 22, height: 20)
        tv.textStorage?.setAttributedString(GuideWindow.attributed())
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        return scroll
    }

    /// Open on the screen under the cursor; NSScreen.main can be an asleep display.
    static func screenUnderCursor() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    static func center(_ w: NSWindow) {
        if let vf = screenUnderCursor()?.visibleFrame {
            w.setFrameOrigin(NSPoint(x: vf.midX - w.frame.width / 2, y: vf.midY - w.frame.height / 2))
        } else {
            w.center()
        }
    }
}
