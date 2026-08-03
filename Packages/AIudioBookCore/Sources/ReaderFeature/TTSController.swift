//
//  TTSController.swift
//  ReaderFeature
//
//  Calls a local OpenAI-compatible TTS server (e.g. Kokoro-FastAPI on localhost:8880).
//  Text is split into sentences with NLTokenizer, then fetched and played one by one via
//  AVAudioPlayer (basic audio playback, no sandbox issues unlike AVSpeechSynthesizer).
//  While sentence N plays, sentence N+1 is already being fetched — latency is minimal
//  after the first sentence. Current sentence is highlighted for karaoke-style tracking.
//

import AVFoundation
import NaturalLanguage
import Observation

@Observable
final class TTSController {

    // MARK: - Voice catalogue

    struct VoiceInfo: Identifiable {
        let id: String
        let displayName: String
        let locale: String
    }

    static let availableVoices: [VoiceInfo] = [
        VoiceInfo(id: "ff_siwis",  displayName: "Siwis",  locale: "fr-FR"),
        VoiceInfo(id: "af_bella",  displayName: "Bella",  locale: "en-US"),
        VoiceInfo(id: "af_sarah",  displayName: "Sarah",  locale: "en-US"),
        VoiceInfo(id: "am_adam",   displayName: "Adam",   locale: "en-US"),
        VoiceInfo(id: "bf_emma",   displayName: "Emma",   locale: "en-GB"),
        VoiceInfo(id: "bm_george", displayName: "George", locale: "en-GB"),
    ]

    // MARK: - Observable state

    var isPlaying = false
    var isPaused  = false
    var isLoading = false
    var currentSentenceRange: NSRange?
    var errorMessage: String?

    var serverURL = "http://localhost:8880"
    var voice     = "ff_siwis"
    var speed: Double = 0.9

    // MARK: - Private types

    private struct Sentence {
        let text: String
        let range: NSRange
    }

    // MARK: - Private state

    private var sentences:    [Sentence] = []
    private var currentIndex  = 0
    private var prefetched:   [Int: Data] = [:]
    private var fetchTasks:   [Int: Task<Data?, Never>] = [:]
    private var playbackTask: Task<Void, Never>?

    // AVAudioPlayer and its delegate are accessed only on main actor (defaultIsolation).
    // The delegate uses nonisolated(unsafe) + NSLock because its callbacks arrive from
    // Core Audio threads, not the main actor.
    private var player:         AVAudioPlayer?
    private var playerDelegate: AudioPlayerDelegate?

    // MARK: - Public API

    func play(text: String, headings: Set<String> = [], from startOffset: Int? = nil) {
        stop()
        let sents = Self.splitSentences(text, headings: headings)
        guard !sents.isEmpty else { return }
        sentences    = sents
        // If the user clicked a specific position, find the sentence that contains it.
        if let offset = startOffset, offset > 0 {
            currentIndex = sents.firstIndex(where: { NSMaxRange($0.range) > offset }) ?? 0
        } else {
            currentIndex = 0
        }
        errorMessage = nil
        isPlaying    = true
        isPaused     = false
        playbackTask = Task { await runPlayback() }
    }

    func pauseResume() {
        if isPaused {
            player?.play()
            isPaused  = false
            isPlaying = true
        } else if isPlaying {
            player?.pause()
            isPaused  = true
            isPlaying = false
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks = [:]
        let d = playerDelegate
        player?.stop()
        player        = nil
        playerDelegate = nil
        d?.resume()           // unblock any in-flight playAudio await
        isPlaying            = false
        isPaused             = false
        isLoading            = false
        currentSentenceRange = nil
        prefetched           = [:]
        sentences            = []
        currentIndex         = 0
    }

    // MARK: - Playback loop

    private func runPlayback() async {
        startFetch(index: 0)
        startFetch(index: 1)
        isLoading = true

        while currentIndex < sentences.count {
            guard !Task.isCancelled else { break }

            let idx = currentIndex

            guard let audioData = await awaitFetch(index: idx) else {
                if !Task.isCancelled {
                    errorMessage         = "Impossible de contacter le serveur TTS à \(serverURL). Vérifiez qu'il est démarré."
                    isPlaying            = false
                    isPaused             = false
                    isLoading            = false
                    currentSentenceRange = nil
                }
                return
            }

            isLoading            = false
            currentSentenceRange = sentences[idx].range

            startFetch(index: idx + 2)

            await playAudio(audioData)

            currentIndex += 1
        }

        if !Task.isCancelled {
            isPlaying            = false
            isPaused             = false
            isLoading            = false
            currentSentenceRange = nil
        }
    }

    private func startFetch(index: Int) {
        guard index < sentences.count, fetchTasks[index] == nil else { return }
        let text = sentences[index].text
        let url  = serverURL
        let v    = voice
        let s    = speed
        fetchTasks[index] = Task {
            try? await Self.fetchAudio(text: text, serverURL: url, voice: v, speed: s)
        }
    }

    private func awaitFetch(index: Int) async -> Data? {
        if let data = prefetched[index] { return data }
        if fetchTasks[index] == nil { startFetch(index: index) }
        let data = await fetchTasks[index]?.value
        if let data { prefetched[index] = data }
        return data
    }

    // MARK: - Audio playback

    private func playAudio(_ data: Data) async {
        let d = AudioPlayerDelegate()
        playerDelegate = d

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                d.setContinuation(cont)
                do {
                    let p = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
                    p.delegate = d
                    player = p
                    p.prepareToPlay()
                    if !p.play() { d.resume() }
                } catch {
                    d.resume()
                }
            }
        } onCancel: {
            d.resume()
        }
    }

    // MARK: - HTTP fetch

    private static func fetchAudio(text: String,
                                   serverURL: String,
                                   voice: String,
                                   speed: Double) async throws -> Data {
        guard let url = URL(string: "\(serverURL)/v1/audio/speech") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "kokoro",
            "input": text,
            "voice": voice,
            "response_format": "mp3",
            "speed": speed,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - Sentence splitting

    private static func splitSentences(_ text: String, headings: Set<String>) -> [Sentence] {
        var result: [Sentence] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                // A sentence is a "heading" if it exactly matches a known heading, or is a
                // prefix of one (handles NLTokenizer splitting "I. Title" into "I." + "Title").
                let isHeading = headings.contains(raw)
                    || headings.contains(where: { $0.hasPrefix(raw + " ") })
                // range stays in original text (for karaoke highlighting); text is preprocessed for TTS.
                result.append(Sentence(text: preprocessForTTS(raw, isHeading: isHeading), range: NSRange(range, in: text)))
            }
            return true
        }
        if result.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isHeading = headings.contains(raw) || headings.contains(where: { $0.hasPrefix(raw + " ") })
            result.append(Sentence(
                text: preprocessForTTS(text, isHeading: isHeading),
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ))
        }
        return result
    }

    // MARK: - TTS text preprocessing

    /// Converts Roman numerals to spoken French words before sending text to the TTS server.
    /// Four passes in order of specificity: chapter context, ordinal suffix, proper noun, period-delimited.
    /// The fourth pass allows single-character numerals ("I.") only when the sentence is a known heading.
    private static func preprocessForTTS(_ text: String, isHeading: Bool = false) -> String {
        var s = text
        s = replaceRomanInChapterContext(s)
        s = replaceRomanOrdinals(s)
        s = replaceRomanAfterProperNoun(s)
        s = replaceRomanWithPeriod(s, inHeading: isHeading)
        return s
    }

    /// "Chapitre XIV" → "Chapitre quatorze"
    private static func replaceRomanInChapterContext(_ text: String) -> String {
        let kw = "chapitre|partie|tome|acte|livre|volume|section|prologue|épilogue|interlude"
        return applyRegex("(?i)\\b(\(kw))\\s+([MDCLXVI]+)\\b", to: text) { match, s in
            let keyword = captureGroup(1, match, s)
            let roman   = captureGroup(2, match, s)
            guard let n = romanToInt(roman.uppercased()), let word = frenchCardinal(n) else { return nil }
            return "\(keyword) \(word)"
        }
    }

    /// "XXe siècle" → "vingtième siècle", "IIème" → "deuxième"
    private static func replaceRomanOrdinals(_ text: String) -> String {
        return applyRegex("\\b([MDCLXVI]{2,})(?:ième|ière|ème|eme|ier|ère|er|e)\\b", to: text) { match, s in
            let roman = captureGroup(1, match, s)
            guard let n = romanToInt(roman), let word = frenchOrdinal(n) else { return nil }
            return word
        }
    }

    /// "II. The best and the worse" → "deux. The best and the worse"
    /// In heading mode, also converts single-char numerals: "I. Title" → "un. Title".
    /// In body mode, requires 2+ chars to avoid misreading initials like "I. Dupont".
    private static func replaceRomanWithPeriod(_ text: String, inHeading: Bool) -> String {
        let pattern = inHeading
            ? "\\b([MDCLXVI]+)\\.(?=\\s+\\S)"
            : "\\b([MDCLXVI]{2,})\\.(?=\\s+[A-ZÁÉÀÈÙÂÔÊÎÛŒÆÇ])"
        return applyRegex(pattern, to: text) { match, s in
            let roman = captureGroup(1, match, s)
            guard let n = romanToInt(roman), let word = frenchCardinal(n) else { return nil }
            return "\(word)."
        }
    }

    /// "Louis XIV" → "Louis quatorze", "Napoléon III" → "Napoléon trois"
    private static func replaceRomanAfterProperNoun(_ text: String) -> String {
        return applyRegex(
            "\\b([A-ZÁÉÀÈÙÂÔÊÎÛŒÆÇ][a-záéàèùâôêîûœæçïëü]+)\\s+([MDCLXVI]{2,})\\b",
            to: text
        ) { match, s in
            let name  = captureGroup(1, match, s)
            let roman = captureGroup(2, match, s)
            guard let n = romanToInt(roman), let word = frenchCardinal(n) else { return nil }
            return "\(name) \(word)"
        }
    }

    private static func applyRegex(
        _ pattern: String,
        to text: String,
        transform: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = "", lastEnd = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[lastEnd..<range.lowerBound]
            result += transform(match, text) ?? String(text[range])
            lastEnd = range.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    private static func captureGroup(_ i: Int, _ match: NSTextCheckingResult, _ text: String) -> String {
        guard let r = Range(match.range(at: i), in: text) else { return "" }
        return String(text[r])
    }

    // MARK: Roman numeral helpers

    private static func romanToInt(_ s: String) -> Int? {
        let map: [Character: Int] = [
            "I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000
        ]
        let upper = s.uppercased()
        guard !upper.isEmpty, upper.allSatisfy({ map[$0] != nil }) else { return nil }
        var total = 0, prev = 0
        for ch in upper.reversed() {
            let val = map[ch]!
            total += val < prev ? -val : val
            prev = val
        }
        return total > 0 && total <= 3999 ? total : nil
    }

    private static func frenchCardinal(_ n: Int) -> String? {
        guard n >= 1, n <= 3999 else { return nil }
        let ones = ["", "un", "deux", "trois", "quatre", "cinq", "six", "sept",
                    "huit", "neuf", "dix", "onze", "douze", "treize", "quatorze",
                    "quinze", "seize", "dix-sept", "dix-huit", "dix-neuf"]

        func below100(_ n: Int) -> String {
            if n < 20 { return ones[n] }
            let t = n / 10, u = n % 10
            switch t {
            case 2, 3, 4, 5, 6:
                let tens = ["vingt", "trente", "quarante", "cinquante", "soixante"][t - 2]
                if u == 0 { return tens }
                return tens + (u == 1 ? " et un" : "-" + ones[u])
            case 7:
                return u == 0 ? "soixante-dix" : "soixante-" + ones[10 + u]
            case 8:
                return u == 0 ? "quatre-vingts" : "quatre-vingt-" + ones[u]
            default: // 9
                return "quatre-vingt-" + ones[10 + u]
            }
        }

        func below1000(_ n: Int) -> String {
            if n < 100 { return below100(n) }
            let h = n / 100, r = n % 100
            if h == 1 { return r == 0 ? "cent" : "cent " + below100(r) }
            let hStr = ones[h] + " cent"
            return r == 0 ? hStr + "s" : hStr + " " + below100(r)
        }

        if n < 1000 { return below1000(n) }
        let th = n / 1000, r = n % 1000
        let prefix = th == 1 ? "mille" : below1000(th) + " mille"
        return r == 0 ? prefix : prefix + " " + below1000(r)
    }

    private static func frenchOrdinal(_ n: Int) -> String? {
        if n == 1 { return "premier" }
        guard var base = frenchCardinal(n) else { return nil }
        if base == "quatre-vingts"    { return "quatre-vingtième" }
        if base.hasSuffix("neuf")     { return String(base.dropLast(4)) + "neuvième" }
        if base.hasSuffix("cinq")     { return String(base.dropLast(4)) + "cinquième" }
        if base.hasSuffix("e")        { base = String(base.dropLast()) }
        return base + "ième"
    }
}

// MARK: - AVAudioPlayer delegate bridge

// Not actor-isolated so that Core Audio can call it from any thread.
// All mutable state is protected by NSLock.
private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {

    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Void, Never>?
    nonisolated(unsafe) private var didResume = false

    func setContinuation(_ c: CheckedContinuation<Void, Never>) {
        lock.lock()
        continuation = c
        lock.unlock()
    }

    nonisolated func resume() {
        lock.lock()
        guard !didResume, let c = continuation else {
            lock.unlock()
            return
        }
        didResume    = true
        continuation = nil
        lock.unlock()
        c.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resume()
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        resume()
    }
}
