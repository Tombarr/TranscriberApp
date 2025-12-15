import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

@main
@available(macOS 26.0, *)
struct TranscriberApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(minWidth: 500, minHeight: 480)
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}

// MARK: - App Delegate

@available(macOS 26.0, *)
class AppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    // Handle opened/dropped files
    for url in urls {
      TranscriptionManager.shared.addFile(url)
    }
  }
}

// MARK: - Content View

@available(macOS 26.0, *)
struct ContentView: View {
  @StateObject private var manager = TranscriptionManager.shared

  private func localeDisplayName(for locale: Locale) -> String {
    let displayName = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    return "\(displayName) (\(locale.identifier))"
  }

  var body: some View {
    VStack(spacing: 20) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "waveform.circle.fill")
          .font(.system(size: 60))
          .foregroundStyle(.blue)

        Text("Audio Transcriber")
          .font(.title)
          .fontWeight(.bold)

        Text("Drag and drop audio files to transcribe")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top, 40)

      // Settings Section
      VStack(spacing: 12) {
        // Format Selection
        HStack {
          Text("Output Format:")
            .font(.headline)
            .frame(width: 120, alignment: .trailing)

          Picker("", selection: $manager.selectedFormat) {
            ForEach(TranscriptFormat.allCases) { format in
              Text(format.description).tag(format)
            }
          }
          .frame(maxWidth: 300)
        }

        // Language Selection
        HStack {
          Text("Language:")
            .font(.headline)
            .frame(width: 120, alignment: .trailing)

          if manager.isLoadingLocales {
            ProgressView()
              .scaleEffect(0.7)
            Text("Loading languages...")
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            Picker("", selection: $manager.selectedLocale) {
              ForEach(manager.availableLocales, id: \.identifier) { locale in
                Text(localeDisplayName(for: locale)).tag(locale)
              }
            }
            .frame(maxWidth: 300)
          }
        }
      }
      .padding(.horizontal)

      // Drop Zone
      DropZoneView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      // Queue List
      if !manager.items.isEmpty {
        List(manager.items) { item in
          TranscriptionItemView(item: item)
        }
        .frame(maxHeight: 200)
      }

      // Status
      HStack {
        Text("\(manager.completed) completed, \(manager.failed) failed")
          .font(.caption)
          .foregroundColor(.secondary)

        Spacer()

        if manager.isProcessing {
          ProgressView()
            .scaleEffect(0.7)
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 16)
    }
  }
}

// MARK: - Drop Zone View

@available(macOS 26.0, *)
struct DropZoneView: View {
  @StateObject private var manager = TranscriptionManager.shared
  @State private var isTargeted = false
  @State private var isShowingFilePicker = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
        .foregroundStyle(isTargeted ? .blue : .gray.opacity(0.5))
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        )
        .padding(18)

      VStack(spacing: 12) {
        Image(systemName: isTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
          .font(.system(size: 48))
          .foregroundStyle(isTargeted ? .blue : .gray)

        Text(isTargeted ? "Drop to transcribe" : "Drop audio files here")
          .font(.headline)
          .foregroundColor(isTargeted ? .blue : .secondary)

        Text("Supported: MP3, M4A, WAV, AIFF")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
      handleDrop(providers: providers)
      return true
    }
    .onTapGesture {
      isShowingFilePicker = true
    }
    .fileImporter(
      isPresented: $isShowingFilePicker,
      allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
      allowsMultipleSelection: true
    ) { result in
      handleFilePickerResult(result)
    }
    .contentShape(Rectangle())
    .buttonStyle(.plain)
  }

  private func handleDrop(providers: [NSItemProvider]) {
    for provider in providers {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url = url, url.isFileURL {
          DispatchQueue.main.async {
            manager.addFile(url)
          }
        }
      }
    }
  }

  private func handleFilePickerResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      for url in urls {
        manager.addFile(url)
      }
    case .failure(let error):
      print("File picker error: \(error.localizedDescription)")
    }
  }
}

// MARK: - Transcription Item View

@available(macOS 26.0, *)
struct TranscriptionItemView: View {
  let item: TranscriptionItem

  var body: some View {
    HStack {
      Image(systemName: statusIcon)
        .foregroundStyle(statusColor)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.fileName)
          .font(.body)

        Text(item.status.description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if item.status == .processing {
        ProgressView()
          .scaleEffect(0.7)
      }
    }
    .padding(.vertical, 4)
  }

  private var statusIcon: String {
    switch item.status {
    case .pending: return "clock"
    case .processing: return "waveform"
    case .completed: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    }
  }

  private var statusColor: Color {
    switch item.status {
    case .pending: return .gray
    case .processing: return .blue
    case .completed: return .green
    case .failed: return .red
    }
  }
}

// MARK: - Transcription Manager

@available(macOS 26.0, *)
@MainActor
class TranscriptionManager: ObservableObject {
  static let shared = TranscriptionManager()

  @Published var items: [TranscriptionItem] = []
  @Published var isProcessing = false
  @Published var selectedFormat: TranscriptFormat = .txt
  @Published var selectedLocale: Locale = Locale(identifier: "en_US")
  @Published var availableLocales: [Locale] = []
  @Published var isLoadingLocales = false

  var completed: Int {
    items.filter { $0.status == .completed }.count
  }

  var failed: Int {
    items.filter {
      if case .failed = $0.status {
        return true
      }
      return false
    }.count
  }

  private let queue = DispatchQueue(label: "com.barrasso.transcriber.queue")

  private init() {
    Task {
      await loadAvailableLocales()
    }
  }

  private func loadAvailableLocales() async {
    isLoadingLocales = true
    let installed = await SpeechTranscriber.installedLocales

    print("DEBUG: Installed locales count: \(installed.count)")
    for locale in installed {
      print("DEBUG: - \(locale.identifier)")
    }

    availableLocales = installed.sorted { locale1, locale2 in
      let name1 = locale1.localizedString(forIdentifier: locale1.identifier) ?? locale1.identifier
      let name2 = locale2.localizedString(forIdentifier: locale2.identifier) ?? locale2.identifier
      return name1 < name2
    }

    // Set default to English if available, otherwise first locale
    if let englishLocale = availableLocales.first(where: { $0.identifier.hasPrefix("en") }) {
      selectedLocale = englishLocale
    } else if let firstLocale = availableLocales.first {
      selectedLocale = firstLocale
    }

    isLoadingLocales = false
  }

  private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
    guard await isSupported(locale: locale) else {
      throw TranscriptionError.languageNotSupported(locale.identifier)
    }

    if await isInstalled(locale: locale) {
      return
    } else {
      try await downloadIfNeeded(for: transcriber)
    }
  }

  private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
    if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
      try await downloader.downloadAndInstall()
    }
  }

  private func isSupported(locale: Locale) async -> Bool {
    let supported = await SpeechTranscriber.supportedLocales
    return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
  }

  private func isInstalled(locale: Locale) async -> Bool {
    let installed = await Set(SpeechTranscriber.installedLocales)
    return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
  }

  func addFile(_ url: URL) {
    // Start accessing security-scoped resource for sandboxed apps
    let accessing = url.startAccessingSecurityScopedResource()

    let item = TranscriptionItem(url: url, isSecurityScoped: accessing)
    items.append(item)
    processNext()
  }

  private func processNext() {
    guard !isProcessing else { return }
    guard let nextItem = items.first(where: { $0.status == .pending }) else { return }

    isProcessing = true
    updateStatus(for: nextItem.id, to: .processing)

    Task {
      await transcribe(item: nextItem)
    }
  }

  private func transcribe(item: TranscriptionItem) async {
    // Ensure we have access to the security-scoped resource
    defer {
      if item.isSecurityScoped {
        item.url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      // Determine output file path based on selected format
      let outputURL = item.url.deletingPathExtension().appendingPathExtension(
        selectedFormat.fileExtension)

      // Configure SpeechTranscriber with selected locale
      let transcriber = SpeechTranscriber(
        locale: selectedLocale,
        transcriptionOptions: [],
        reportingOptions: [],
        attributeOptions: [.audioTimeRange]
      )

      // Ensure language model is installed
      print("DEBUG: Ensuring model for locale: \(selectedLocale.identifier)")
      do {
        try await ensureModel(for: transcriber, locale: selectedLocale)
        print("DEBUG: Model ensured successfully")
      } catch {
        print("DEBUG: Model ensure failed: \(error)")
        await markAsFailed(
          item: item, error: "Language model not available: \(error.localizedDescription)")
        return
      }

      // Create analyzer with transcriber
      let analyzer = SpeechAnalyzer(modules: [transcriber])

      // Verify file exists and is accessible
      guard FileManager.default.fileExists(atPath: item.url.path) else {
        await markAsFailed(item: item, error: "File not found at path: \(item.url.path)")
        return
      }

      // Open audio file
      let audioFile: AVAudioFile
      do {
        audioFile = try AVAudioFile(forReading: item.url)
      } catch {
        await markAsFailed(
          item: item,
          error: "Cannot open audio file: \(error.localizedDescription). File: \(item.url.path)")
        return
      }

      // Analyze the audio
      async let transcriptionFuture = try transcriber.results.reduce(AttributedString("")) {
        str, result in
        return str + result.text
      }

      if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
        try await analyzer.finalizeAndFinish(through: lastSample)
      } else {
        await analyzer.cancelAndFinishNow()
      }

      // Get aggregated transcription
      let aggregated = try await transcriptionFuture

      print("DEBUG: Transcription completed. Character count: \(aggregated.characters.count)")

      // Check if we actually got any transcription
      guard !aggregated.characters.isEmpty else {
        await markAsFailed(
          item: item,
          error: "No transcription produced. The speech model may not be properly installed.")
        return
      }

      // Generate output based on selected format
      let outputText: String
      if selectedFormat == .srt {
        outputText = generateSRT(from: aggregated)
      } else {
        outputText = String(aggregated.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      }

      print("DEBUG: Output text length: \(outputText.count)")
      print("DEBUG: Writing to: \(outputURL.path)")

      // Write to file
      try outputText.write(to: outputURL, atomically: true, encoding: .utf8)

      print("DEBUG: File written successfully")

      // Mark as completed
      updateStatus(for: item.id, to: .completed)
      isProcessing = false
      processNext()

    } catch {
      await markAsFailed(item: item, error: error.localizedDescription)
    }
  }

  private func generateSRT(from attributed: AttributedString) -> String {
    // Convert AttributedString with timing info to segments
    var segments: [TranscriptionSegment] = []

    for run in attributed.runs {
      let runText = String(attributed[run.range].characters).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard !runText.isEmpty else { continue }

      if let timeRange = run.audioTimeRange {
        let timestamp = CMTimeGetSeconds(timeRange.start)
        let duration = CMTimeGetSeconds(timeRange.end) - timestamp

        segments.append(
          TranscriptionSegment(
            text: runText,
            timestamp: timestamp,
            duration: duration
          ))
      }
    }

    // Merge segments into subtitle chunks (max 80 chars, max 6 seconds)
    let mergedSegments = mergeSegments(segments, maxCharsPerLine: 80, maxDurationPerSubtitle: 6.0)

    // Format as SRT
    let formatter = SRTFormatter()
    return formatter.format(segments: mergedSegments)
  }

  private func mergeSegments(
    _ segments: [TranscriptionSegment], maxCharsPerLine: Int, maxDurationPerSubtitle: Double
  ) -> [TranscriptionSegment] {
    var merged: [TranscriptionSegment] = []
    var currentText = ""
    var currentTimestamp: Double?
    var currentDuration: Double = 0

    for segment in segments {
      if currentTimestamp == nil {
        currentTimestamp = segment.timestamp
        currentText = segment.text
        currentDuration = segment.duration
      } else {
        let totalDuration = (segment.timestamp + segment.duration) - currentTimestamp!
        let exceedsMaxDuration = totalDuration > maxDurationPerSubtitle
        let exceedsMaxChars = (currentText.count + segment.text.count + 1) > maxCharsPerLine
        let endsWithSentence = currentText.last.map { ".!?".contains($0) } ?? false

        if exceedsMaxDuration || exceedsMaxChars || endsWithSentence {
          merged.append(
            TranscriptionSegment(
              text: currentText,
              timestamp: currentTimestamp!,
              duration: currentDuration
            ))
          currentTimestamp = segment.timestamp
          currentText = segment.text
          currentDuration = segment.duration
        } else {
          currentText += " " + segment.text
          currentDuration = (segment.timestamp + segment.duration) - currentTimestamp!
        }
      }
    }

    if let timestamp = currentTimestamp, !currentText.isEmpty {
      merged.append(
        TranscriptionSegment(
          text: currentText,
          timestamp: timestamp,
          duration: currentDuration
        ))
    }

    return merged
  }

  private func markAsFailed(item: TranscriptionItem, error: String) async {
    await MainActor.run {
      updateStatus(for: item.id, to: .failed(error))
      isProcessing = false
      processNext()
    }
  }

  private func updateStatus(for id: UUID, to status: TranscriptionStatus) {
    if let index = items.firstIndex(where: { $0.id == id }) {
      items[index].status = status
    }
  }
}

// MARK: - Models

struct TranscriptionItem: Identifiable {
  let id = UUID()
  let url: URL
  let isSecurityScoped: Bool
  var status: TranscriptionStatus = .pending

  var fileName: String {
    url.lastPathComponent
  }
}

enum TranscriptionStatus: Equatable {
  case pending
  case processing
  case completed
  case failed(String)

  var description: String {
    switch self {
    case .pending: return "Waiting..."
    case .processing: return "Transcribing..."
    case .completed: return "Completed"
    case .failed(let error): return "Failed: \(error)"
    }
  }
}

enum TranscriptionError: Error, LocalizedError {
  case languageNotSupported(String)
  case modelDownloadFailed(String)

  var errorDescription: String? {
    switch self {
    case .languageNotSupported(let locale):
      return "Language '\(locale)' is not supported by Speech Analyzer"
    case .modelDownloadFailed(let reason):
      return "Failed to download language model: \(reason)"
    }
  }
}
