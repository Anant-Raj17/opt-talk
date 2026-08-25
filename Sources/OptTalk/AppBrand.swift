import AppKit

enum AppBrand {
    static let emoji = "🗣️"
    static let name = "opt-talk"

    /// Menu bar glyph sized for the status item (~18pt slot).
    static func menuBarImage() -> NSImage {
        emojiImage(pointSize: 16, canvas: NSSize(width: 22, height: 18))
    }

    static func emojiImage(pointSize: CGFloat, canvas: NSSize) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: pointSize)
            ]
            let string = emoji as NSString
            let textSize = string.size(withAttributes: attrs)
            let origin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2 - 1
            )
            string.draw(at: origin, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = name
        return image
    }

    static func applyApplicationIcon() {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
            return
        }
        NSApp.applicationIconImage = emojiImage(
            pointSize: 512,
            canvas: NSSize(width: 512, height: 512)
        )
    }
}
