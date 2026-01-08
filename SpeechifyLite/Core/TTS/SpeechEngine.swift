//
//  SpeechEngine.swift
//  SpeechifyLite
//
//  Created by Omid Shojaeian Zanjani on 07/01/26.
//
import Foundation
import Combine
import AVFoundation
struct VoiceOption: Identifiable, Hashable {
    let id: String?   // nil = System Default
    let name: String
}

final class SpeechEngine: NSObject, ObservableObject {
    enum State { case idle, speaking, paused }

    @Published private(set) var state: State = .idle

    @Published var selectedLanguageCode: String = SpeechEngine.normalizeLanguage(Locale.current.identifier)
    @Published var selectedVoiceID: String? = nil
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    // Published speaking range (character range within the utterance's string) so the UI can highlight
    @Published var speakingRange: NSRange = NSRange(location: NSNotFound, length: 0)

    private let synthesizer = AVSpeechSynthesizer()

    // Cache AVSpeechSynthesisVoice list for the current language to avoid repeatedly calling
    // AVSpeechSynthesisVoice.speechVoices() on each SwiftUI view update (this reduces system activity
    // that can lead to ViewBridge/remote view messages).
    private var currentAVVoices: [AVSpeechSynthesisVoice] = []
    private var cachedVoiceOptions: [VoiceOption] = []

    // Cache all AVSpeechSynthesisVoice objects once at startup to avoid repeated system queries.
    static let allAVVoices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()

    // Cache available languages once (use the cached allAVVoices)
    static let cachedLanguages: [String] = {
        let langs = Set(allAVVoices.map { $0.language })
        return Array(langs).sorted()
    }()

    var availableLanguages: [String] { Self.cachedLanguages }

    var voiceOptions: [VoiceOption] {
        cachedVoiceOptions
    }
    @Published var selectedVoiceIndex: Int = 0

    override init() {
        super.init()
        synthesizer.delegate = self

        let langs = Self.cachedLanguages
        if !langs.contains(selectedLanguageCode) {
            selectedLanguageCode = langs.first(where: { $0.hasPrefix("en") }) ?? (langs.first ?? "en-US")
        }
        // Default to System Default (index 0) if no explicit selection available
        selectedVoiceID = nil
        selectedVoiceIndex = 0

        // Build caches for the initial language synchronously
        rebuildVoiceCacheForCurrentLanguageSync()
        // Ensure the index and id are consistent with available voices
        validateSelection()
    }

    // Convert "en_US" -> "en-US"
    static func normalizeLanguage(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-")
    }

    static func availableLanguages() -> [String] {
        cachedLanguages
    }

    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        let code = normalizeLanguage(languageCode)
        // Filter from the cached global list to avoid calling speechVoices() repeatedly
        return allAVVoices
            .filter { $0.language == code }
            .sorted { $0.name < $1.name }
    }

    static func displayName(for languageCode: String) -> String {
        let code = normalizeLanguage(languageCode)
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code) ?? code
    }

    private func rebuildVoiceCacheForCurrentLanguageSync() {
        // Synchronous cache rebuild (used at init)
        let voices = Self.voices(for: selectedLanguageCode)
        currentAVVoices = voices
        var result: [VoiceOption] = [VoiceOption(id: nil, name: "System Default")]
        result += voices.map { VoiceOption(id: $0.identifier, name: $0.name) }
        cachedVoiceOptions = result
    }

    private func rebuildVoiceCacheForCurrentLanguageAsync() {
        let language = selectedLanguageCode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let voices = Self.voices(for: language)
            var result: [VoiceOption] = [VoiceOption(id: nil, name: "System Default")]
            result += voices.map { VoiceOption(id: $0.identifier, name: $0.name) }
            DispatchQueue.main.async {
                // Only apply if the language hasn't changed again
                if self.selectedLanguageCode == language {
                    self.currentAVVoices = voices
                    self.cachedVoiceOptions = result
                    self.validateSelection()
                }
            }
        }
    }

    func updateLanguage(_ newLanguage: String) {
        let normalized = Self.normalizeLanguage(newLanguage)
        // change language and reset selection to a valid state (System Default)
        selectedLanguageCode = normalized
        // rebuild cache for new language asynchronously to avoid main thread/service churn
        rebuildVoiceCacheForCurrentLanguageAsync()
        // prefer System Default on language change to avoid mismatches
        selectedVoiceIndex = 0
        selectedVoiceID = nil
        validateSelection()
    }


    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        // Use the exact string provided for the utterance so that character ranges provided by the
        // `willSpeakRangeOfSpeechString` delegate are aligned with the UI text.
        let utterance = AVSpeechUtterance(string: text)
        
        utterance.rate = rate
        applySelectedVoice(to: utterance)

        // start speaking
        synthesizer.speak(utterance)
        state = .speaking

    }

    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        // clear highlighting when stopped
        DispatchQueue.main.async { [weak self] in
            self?.speakingRange = NSRange(location: NSNotFound, length: 0)
        }
    }
    func validateSelection() {
        // Ensure selectedVoiceIndex is within bounds for current voiceOptions
        let count = cachedVoiceOptions.count
        if count == 0 {
            selectedVoiceIndex = 0
            selectedVoiceID = nil
            return
        }

        if selectedVoiceIndex < 0 || selectedVoiceIndex >= count {
            // clamp to System Default
            selectedVoiceIndex = 0
        }

        // Sync selectedVoiceID with selectedVoiceIndex
        let opt = cachedVoiceOptions[selectedVoiceIndex]
        selectedVoiceID = opt.id

        // Extra safety: if selectedVoiceID is non-nil but the underlying AVSpeechSynthesisVoice no longer exists,
        // fall back to system default
        if let id = selectedVoiceID {
            let availableIDs = Set(currentAVVoices.map { $0.identifier })
            if !availableIDs.contains(id) {
                selectedVoiceIndex = 0
                selectedVoiceID = nil
            }
        }
    }
    func applySelectedVoice(to utterance: AVSpeechUtterance) {
        let options = cachedVoiceOptions
        guard options.indices.contains(selectedVoiceIndex),
              let id = options[selectedVoiceIndex].id,
              let voice = AVSpeechSynthesisVoice(identifier: id)
        else {
            utterance.voice = AVSpeechSynthesisVoice(language: selectedLanguageCode)
            return
        }

        utterance.voice = voice
    }

    // Helper: whether Persian (fa) language voices exist
    var isPersianAvailable: Bool {
        let langs = Self.cachedLanguages
        return langs.contains(where: { $0.hasPrefix("fa") || $0 == "fa-IR" })
    }

    // Expand a given characterRange to nearest word boundaries using whitespace/punctuation as separators
    private func expandRangeToWordBoundaries(in string: NSString, range: NSRange) -> NSRange {
        if range.location == NSNotFound || string.length == 0 { return NSRange(location: NSNotFound, length: 0) }

        let full = NSRange(location: 0, length: string.length)
        var start = range.location
        var end = range.location + range.length

        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)

        // Move start backward until preceding char is a separator or we're at 0
        while start > 0 {
            let prevRange = NSRange(location: start - 1, length: 1)
            let ch = string.substring(with: prevRange)
            if ch.rangeOfCharacter(from: separators) != nil { break }
            start -= 1
        }

        // Move end forward until next char is a separator or at end
        while end < string.length {
            let nextRange = NSRange(location: end, length: 1)
            let ch = string.substring(with: nextRange)
            if ch.rangeOfCharacter(from: separators) != nil { break }
            end += 1
        }

        let expanded = NSRange(location: start, length: max(0, end - start))
        return NSIntersectionRange(expanded, full)
    }

}

extension SpeechEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.state = .idle
            self?.speakingRange = NSRange(location: NSNotFound, length: 0)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // Update published range so UI can highlight. Expand to word boundaries for nicer highlighting.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let s = (utterance.speechString as NSString)
            let expanded = self.expandRangeToWordBoundaries(in: s, range: characterRange)
            self.speakingRange = expanded
        }
    }
}
