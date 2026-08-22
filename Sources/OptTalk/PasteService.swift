import AppKit
import Foundation

enum PasteService {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var mapped: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    mapped[type] = data
                }
            }
            return mapped.isEmpty ? nil : mapped
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        func key(_ keyCode: CGKeyCode, down: Bool) {
            let source = CGEventSource(stateID: .hidSystemState)
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        // kVK_ANSI_V
        key(9, down: true)
        key(9, down: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard let previous, !previous.isEmpty else { return }
            pasteboard.clearContents()
            for itemMap in previous {
                let item = NSPasteboardItem()
                for (type, data) in itemMap {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }
}
