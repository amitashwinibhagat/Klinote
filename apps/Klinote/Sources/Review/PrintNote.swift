//
// PrintNote.swift
//
// A letter or a patient's copy has to be able to leave as paper. Prints the
// paste-ready text, so what comes off the printer is exactly what the record
// system would have received.
//

import AppKit

enum PrintNote {
    static func run(for note: ClinicalNote, patientRef: String, title: String) {
        guard let text = try? KlinoteCore.recordText(for: note), !text.isEmpty else {
            NSSound.beep()
            return
        }

        let width: CGFloat = 540
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 720))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 12)

        let heading = NSMutableAttributedString(string: "\(title)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        heading.append(NSAttributedString(string: "\(patientRef)\n\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]))
        heading.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ]))
        heading.addParagraphStyle(lineHeight: 1.35)
        textView.textStorage?.setAttributedString(heading)
        textView.sizeToFit()

        let info = NSPrintInfo.shared
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.run()
    }
}

private extension NSMutableAttributedString {
    /// Line height for the printed letter. Set on the whole string, because a
    /// paragraph style overrides the font's own leading.
    func addParagraphStyle(lineHeight: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: length)
        )
    }
}
