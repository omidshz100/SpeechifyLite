//
//  ReaderView.swift
//  SpeechifyLite
//
//  Created by Omid Shojaeian Zanjani on 07/01/26.
//


import SwiftUI
import AVFoundation
import AppKit

// A macOS NSTextView-backed editor that supports attributed highlighting of a character range.
struct AttributedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlightRange: NSRange
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Initialize content
        textView.string = text
        applyHighlight(in: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        textView.isEditable = isEditable

        // If the NSTextView content differs from binding, update it (avoid moving cursor unnecessarily)
        if textView.string != text {
            // preserve selected range
            let sel = textView.selectedRange()
            textView.string = text
            let newSel = NSIntersectionRange(sel, NSRange(location: 0, length: textView.string.count))
            textView.setSelectedRange(newSel)
        }

        applyHighlight(in: textView)
    }

    private func applyHighlight(in textView: NSTextView) {
        // Build attributed string with base attributes and apply highlight for highlightRange.
        let full = textView.string
        let attr = NSMutableAttributedString(string: full)
        let fullRange = NSRange(location: 0, length: attr.length)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        attr.addAttribute(.font, value: font, range: fullRange)
        attr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        if highlightRange.location != NSNotFound && highlightRange.length > 0 && NSIntersectionRange(highlightRange, fullRange).length > 0 {
            let intersection = NSIntersectionRange(highlightRange, fullRange)
            let highlightColor = NSColor.systemBlue.withAlphaComponent(0.25)
            attr.addAttribute(.backgroundColor, value: highlightColor, range: intersection)
        }

        // Apply attributes without moving insertion point
        let selected = textView.selectedRange()
        textView.textStorage?.setAttributedString(attr)
        textView.setSelectedRange(selected)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AttributedTextEditor
        weak var textView: NSTextView?
        private var isUpdatingFromTextView = false

        init(_ parent: AttributedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Prevent feedback loop
            guard !isUpdatingFromTextView else { return }
            isUpdatingFromTextView = true
            parent.text = tv.string
            isUpdatingFromTextView = false
        }
    }
}

struct ReaderView: View {
    @State private var text: String = "سلام! اینجا متن رو بنویس و Speak رو بزن."
    @StateObject private var engine = SpeechEngine()

    private var languages: [String] { SpeechEngine.availableLanguages() }

    var body: some View {
        VStack(spacing: 12) {
            Text("SpeechifyLite (macOS)")
                .font(.title2)

            HStack(spacing: 12) {
                Picker("Language", selection: $engine.selectedLanguageCode) {
                    ForEach(languages, id: \.self) { code in
                        Text(SpeechEngine.displayName(for: code)).tag(code)
                    }
                }
                .onChange(of: engine.selectedLanguageCode) { _, newValue in
                    engine.updateLanguage(newValue)
                }

                // Voice picker uses integer index tags to avoid SwiftUI Picker tag/selection mismatches
                Picker("Voice", selection: $engine.selectedVoiceIndex) {
                    ForEach(engine.voiceOptions.indices, id: \.self) { idx in
                        Text(engine.voiceOptions[idx].name).tag(idx)
                    }
                }
                // Disable if there are no language-specific voices (only System Default exists)
                .disabled(engine.voiceOptions.count <= 1)
                .onChange(of: engine.selectedVoiceIndex) { _, _ in
                    engine.validateSelection()
                }
            }

            HStack {
                Text("Speed")
                Slider(value: $engine.rate, in: 0.3...0.6)
                    .frame(width: 220)
                Text(String(format: "%.2f", engine.rate))
                    .font(.system(.caption, design: .monospaced))
            }

            // Replace SwiftUI TextEditor with our AttributedTextEditor which supports highlighting
            AttributedTextEditor(text: $text, highlightRange: engine.speakingRange, isEditable: engine.state != .speaking)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                )

            HStack(spacing: 10) {
                Button("Speak") { engine.speak(text) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Pause") { engine.pause() }
                    .disabled(engine.state != .speaking)

                Button("Resume") { engine.resume() }
                    .disabled(engine.state != .paused)

                Button("Stop") { engine.stop() }
                    .disabled(engine.state == .idle)
            }
        }
        .onAppear(){
                engine.validateSelection()
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
    }
}
