# SpeechifyLite

Lightweight macOS text-to-speech app using AVFoundation (AVSpeechSynthesizer).

Features
- Language picker populated from system voices
- Voice picker (System Default + per-language voices) with a stable index-based selection (avoids SwiftUI Picker tag mismatches)
- Speed slider controls speech rate
- Speak / Pause / Resume / Stop controls
- Live word-by-word highlighting while speaking (uses AVSpeechSynthesizer delegate ranges, expanded to word boundaries)
- Persian (fa-IR) availability helper
- Caching of AV speech voices to reduce system/service churn and noisy ViewBridge logs

Files of interest
- `SpeechifyLite/Core/TTS/SpeechEngine.swift` — core TTS engine, voice caching, selection validation, and speaking/highlighting logic.
- `SpeechifyLite/Features/Reader/ReaderView.swift` — main UI; includes an `AttributedTextEditor` (NSTextView-backed) that shows the highlighted speaking range.

Build & run
1. Open `SpeechifyLite/SpeechifyLite.xcodeproj` in Xcode.
2. Select the macOS target and run on your Mac.

Notes & behavior
- The Voice picker binds to an integer index (`selectedVoiceIndex`) instead of a dynamic `String?` identifier to prevent SwiftUI Picker warnings about invalid tags.
- When you change the language, the selected voice resets to a valid choice (System Default by default) to avoid invalid selection state.
- The app caches `AVSpeechSynthesisVoice.speechVoices()` and per-language voice lists at startup (and rebuilds per-language caches asynchronously) to reduce repeated system calls that can trigger ViewBridge / remote view messages in the macOS console.
- While speech is active, the text editor is made read-only to avoid edits that would desync highlight ranges. The highlighted range is cleared when speech finishes or is stopped.

Highlighting behavior
- The app receives character ranges from AVSpeechSynthesizer via `willSpeakRangeOfSpeechString`. To present pleasant highlighting the engine expands those ranges to word boundaries (whitespace/punctuation/symbol separators).
- For scripts without whitespace-based word boundaries (eg. Chinese/Japanese) consider adding `NSLinguisticTagger`-based tokenization for improved results.

Troubleshooting
- If you see system logs about ViewBridge or task ports, the app already reduces that noise by caching voice queries. If you still see messages occasionally, they are usually benign system-level logs related to remote services. To further reduce them, avoid repeatedly toggling language/voice rapidly.
- If speech doesn't start, check macOS sound/output settings and ensure a voice is available for the selected language.

Contributing
- Contributions are welcome. Please fork and open pull requests. If you'd like me to add features (auto-scroll while highlighting, language-aware tokenization, persistence of preferences), tell me which and I'll implement them.

License
- No license is included by default. Add a LICENSE file (for example MIT) if you plan to publish this project.

Contact
- For feature requests or bugs, open an issue in your git hosting or contact the maintainer.

---
Generated: January 8, 2026
