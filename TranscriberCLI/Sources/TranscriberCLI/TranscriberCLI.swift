import Darwin
import Speech

// MARK: - Output Models
struct TranscriptionResult: Codable {
  let success: Bool
  let outputPath: String?
  let error: String?
  let duration: Double?
  let elapsedTime: Double?
}

// MARK: - Subtitle Segment
struct SubtitleChunk {
  var text: String
  var start: CMTime
  var end: CMTime
}

// MARK: - Console Progress
struct ConsoleProgressBar {
  let width: Int = 40

  func render(progress: Double) {
    let clamped = min(max(progress, 0), 1)
    let filled = Int(Double(width) * clamped)
    let empty = width - filled

    let bar =
      String(repeating: "█", count: filled)
      + String(repeating: "░", count: empty)

    let percent = Int(clamped * 100)
    print("\r[\(bar)] \(percent)%", terminator: "")
    fflush(stdout)
  }

  func finish() {
    render(progress: 1)
    print()
  }
}

// MARK: - Transcriber
@available(macOS 26.0, *)
class AudioTranscriber {
  private let audioURL: URL
  private let outputURL: URL
  private let locale: Locale
  private let format: String

  init(audioPath: String, outputPath: String, locale: Locale, format: String) throws {
    guard FileManager.default.fileExists(atPath: audioPath) else {
      throw TranscriptionError.fileNotFound(audioPath)
    }

    self.audioURL = URL(fileURLWithPath: audioPath)
    self.outputURL = URL(fileURLWithPath: outputPath)
    self.locale = locale
    self.format = format
  }

  public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
    guard await supported(locale: locale) else {
      throw TranscriptionError.analyzerCreationFailed("Language not supported")
    }

    if await installed(locale: locale) {
      return
    } else {
      try await downloadIfNeeded(for: transcriber)
    }
  }

  func downloadIfNeeded(for module: SpeechTranscriber) async throws {
    if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
      try await downloader.downloadAndInstall()
    }
  }

  func supported(locale: Locale) async -> Bool {
    let supported = await SpeechTranscriber.supportedLocales
    return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
  }

  func installed(locale: Locale) async -> Bool {
    let installed = await Set(SpeechTranscriber.installedLocales)
    return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
  }

  func mergeRunsToSubtitles(
    from attributed: AttributedString,
    maxCharsPerLine: Int = 80,
    maxDurationPerSubtitle: Double = 6.0
  ) -> [SubtitleChunk] {

    var subtitles: [SubtitleChunk] = []
    var currentText = ""
    var currentStart: CMTime?
    var currentEnd: CMTime?

    for run in attributed.runs {
      let runText = String(attributed[run.range].characters).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard !runText.isEmpty else { continue }

      guard let timeRange = run.audioTimeRange else { continue }
      let runStart = timeRange.start
      let runEnd = timeRange.end

      if currentStart == nil {
        // start new chunk
        currentStart = runStart
        currentEnd = runEnd
        currentText = runText
      } else {
        let duration = CMTimeGetSeconds(runEnd) - CMTimeGetSeconds(currentStart!)
        let exceedsMaxDuration = duration > maxDurationPerSubtitle
        let exceedsMaxChars = (currentText.count + runText.count + 1) > maxCharsPerLine
        let endsWithSentence = currentText.last.map { ".!?".contains($0) } ?? false

        if exceedsMaxDuration || exceedsMaxChars || endsWithSentence {
          // commit current chunk
          subtitles.append(
            SubtitleChunk(
              text: currentText,
              start: currentStart!,
              end: currentEnd!))
          // start new chunk
          currentStart = runStart
          currentEnd = runEnd
          currentText = runText
        } else {
          // extend current chunk
          currentText += " " + runText
          currentEnd = runEnd
        }
      }
    }

    // commit last chunk
    if let start = currentStart, let end = currentEnd, !currentText.isEmpty {
      subtitles.append(
        SubtitleChunk(
          text: currentText,
          start: start,
          end: end))
    }

    return subtitles
  }

  func formatSRTTime(_ time: CMTime) -> String {
    let seconds = CMTimeGetSeconds(time)
    let hours = Int(seconds / 3600)
    let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
    let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
    let millis = Int((seconds - floor(seconds)) * 1000)

    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
  }

  func srt(from chunks: [SubtitleChunk]) -> String {
    var srtLines: [String] = []

    for (index, chunk) in chunks.enumerated() {
      let start = formatSRTTime(chunk.start)
      let end = formatSRTTime(chunk.end)

      srtLines.append(
        """
        \(index + 1)
        \(start) --> \(end)
        \(chunk.text)

        """)
    }

    return srtLines.joined()
  }

  func srt(from attributed: AttributedString) -> String {
    let chunks = mergeRunsToSubtitles(from: attributed)
    return srt(from: chunks)
  }

  func transcribe() async throws -> TranscriptionResult {
    let startTime = Date()
    let progressBar = ConsoleProgressBar()
    var maxProcessedTime: Double = 0

    // PHASE 1: Analyzer Setup
    let transcriber = SpeechTranscriber(
      locale: locale, transcriptionOptions: [],
      reportingOptions: [], attributeOptions: [.audioTimeRange]
    )

    // PHASE 2: Asset Preparation
    do {
      try await ensureModel(transcriber: transcriber, locale: locale)
    } catch {
      throw error
    }

    let analyzer: SpeechAnalyzer = SpeechAnalyzer(modules: [transcriber])

    let audioFile = try AVAudioFile(forReading: audioURL)
    let totalDurationSeconds =
      Double(audioFile.length) / audioFile.processingFormat.sampleRate

    // PHASE 3: Analysis
    async let transcriptionFuture = try transcriber.results
      .reduce(AttributedString("")) {
        str, result in

        for run in result.text.runs {
          if let range = run.audioTimeRange {
            let endSeconds = CMTimeGetSeconds(range.end)
            maxProcessedTime = max(maxProcessedTime, endSeconds)
          }
        }

        let progress = maxProcessedTime / totalDurationSeconds
        progressBar.render(progress: progress)

        return str + result.text
      }

    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
      try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
      await analyzer.cancelAndFinishNow()
    }

    // PHASE 4: Output Generation
    // Await the non-optional aggregated transcription
    let aggregated = try await transcriptionFuture

    // Ensure we write a String to disk. If the reducer yielded AttributedString,
    // convert it to a String; otherwise, use the String directly.
    if self.format.lowercased() == "srt" {
      let outputSrt = srt(from: aggregated)
      try outputSrt.write(to: outputURL, atomically: true, encoding: .utf8)
    } else {
      let stringToWrite = String(aggregated.characters)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      try stringToWrite.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    let elapsedTime: TimeInterval = Date().timeIntervalSince(startTime)

    progressBar.finish()
    return TranscriptionResult(
      success: true,
      outputPath: outputURL.path,
      error: nil,
      duration: totalDurationSeconds,
      elapsedTime: elapsedTime
    )
  }
}

// MARK: - Errors

enum TranscriptionError: Error, CustomStringConvertible {
  case invalidArguments
  case fileNotFound(String)
  case unsupportedMacOSVersion
  case analyzerCreationFailed(String)
  case analysisFailed(String)
  case fileWriteFailed(String)
  case assetNotFound(String)
  case modelDownloadFailed(String)
  case unknownAssetState

  var description: String {
    switch self {
    case .invalidArguments:
      return
        "Invalid arguments. Usage: TranscriberCLI <audio_path> <output_srt_path> <language_code>"
    case .fileNotFound(let path):
      return "Audio file not found: \(path)"
    case .unsupportedMacOSVersion:
      return "SpeechAnalyzer requires macOS 26.0+ (macOS Tahoe). Current version is not supported."
    case .analyzerCreationFailed(let reason):
      return "Failed to create SpeechAnalyzer: \(reason)"
    case .analysisFailed(let reason):
      return "Speech analysis failed: \(reason)"
    case .fileWriteFailed(let reason):
      return "Failed to write SRT file: \(reason)"
    case .assetNotFound(let locale):
      return "No transcription model found in AssetInventory for locale: \(locale)"
    case .modelDownloadFailed(let reason):
      return "Failed to download required speech model: \(reason)"
    case .unknownAssetState:
      return "AssetInventory returned an unknown state."
    }
  }
}

// MARK: - Main

@main
@available(macOS 26.0, *)
struct TranscriberCLI {
  static func main() async {
    var audioPath: String?
    var outputPath: String?
    var format = "txt"
    var languageCode = Locale.current.identifier

    var it = CommandLine.arguments.dropFirst().makeIterator()

    // Load CLI arguments
    while let arg = it.next() {
      switch arg {
      case "--input-path": audioPath = it.next()
      case "--output-path": outputPath = it.next()
      case "--locale": languageCode = it.next() ?? languageCode
      case "--format": format = it.next()?.lowercased() ?? format
      default: Help.exit()
      }
    }

    // Ensure required arguments are present
    guard let inPath = audioPath, let outPath = outputPath else {
      Help.exit()
    }

    do {
      let transcriber = try AudioTranscriber(
        audioPath: inPath,
        outputPath: outPath,
        locale: Locale(identifier: languageCode),
        format: format
      )

      let result = try await transcriber.transcribe()
      printJSON(result)
      Darwin.exit(EXIT_SUCCESS)

    } catch let error as TranscriptionError {
      let result = TranscriptionResult(
        success: false,
        outputPath: nil,
        error: error.description,
        duration: nil,
        elapsedTime: nil
      )
      printJSON(result)

      if case .unsupportedMacOSVersion = error {
        Darwin.exit(2)
      } else {
        Darwin.exit(EXIT_FAILURE)
      }

    } catch {
      let result = TranscriptionResult(
        success: false,
        outputPath: nil,
        error: "Unknown error: \(error.localizedDescription)",
        duration: nil,
        elapsedTime: nil
      )
      printJSON(result)
      Darwin.exit(EXIT_FAILURE)
    }
  }

  static func printJSON<T: Codable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    if let data = try? encoder.encode(value),
      let jsonString = String(data: data, encoding: .utf8)
    {
      print(jsonString)
    }
  }
}

enum Help {
  static func exit() -> Never {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "TranscriberCLI"
    fputs(
      """
      Usage: \(prog) --input-path <file> --output-path <file> [--format txt|srt] [--locale <id>]

      Example:
        .build/release/\(prog) --input-path ABC123.mp3 \
                               --output-path ABC123.srt \
                               --format srt
                               --locale en-US

      """, stderr)
    Darwin.exit(EXIT_FAILURE)
  }
}
