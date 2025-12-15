import Foundation

// MARK: - Transcription Segment

/// Represents a single segment of transcribed audio with timing information
struct TranscriptionSegment {
  let text: String
  let timestamp: Double  // Start time in seconds
  let duration: Double  // Duration in seconds
}

// MARK: - Output Format

enum TranscriptFormat: String, CaseIterable, Identifiable {
  case srt = "SRT"
  case txt = "TXT"

  var id: String { rawValue }

  var fileExtension: String {
    switch self {
    case .srt: return "srt"
    case .txt: return "txt"
    }
  }

  var description: String {
    switch self {
    case .srt: return "SubRip (SRT) - Subtitles with timestamps"
    case .txt: return "Plain Text (TXT) - Text only, no timestamps"
    }
  }
}

// MARK: - Transcript Formatter Protocol

protocol TranscriptFormatter {
  func format(segments: [TranscriptionSegment]) -> String
}

// MARK: - SRT Formatter

struct SRTFormatter: TranscriptFormatter {

  func format(segments: [TranscriptionSegment]) -> String {
    var srtContent = ""

    for (index, segment) in segments.enumerated() {
      let sequenceNumber = index + 1
      let startTime = formatTime(segment.timestamp)
      let endTime = formatTime(segment.timestamp + segment.duration)

      // Sequence number
      srtContent += "\(sequenceNumber)\n"

      // Time range
      srtContent += "\(startTime) --> \(endTime)\n"

      // Subtitle text
      srtContent += "\(segment.text)\n"

      // Blank line separator (except after last segment)
      if index < segments.count - 1 {
        srtContent += "\n"
      }
    }

    return srtContent
  }

  private func formatTime(_ seconds: Double) -> String {
    let hours = Int(seconds / 3600)
    let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
    let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
  }
}

// MARK: - Plain Text Formatter

struct PlainTextFormatter: TranscriptFormatter {

  var includeTimestamps: Bool = false
  var timestampFormat: TimestampFormat = .readable

  enum TimestampFormat {
    case readable  // [00:01:23]
    case seconds  // [83.5s]
    case none
  }

  func format(segments: [TranscriptionSegment]) -> String {
    var textContent = ""

    for segment in segments {
      if includeTimestamps && timestampFormat != .none {
        let timestamp = formatTimestamp(segment.timestamp)
        textContent += "\(timestamp) "
      }

      textContent += segment.text
      textContent += "\n"
    }

    return textContent.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func formatTimestamp(_ seconds: Double) -> String {
    switch timestampFormat {
    case .readable:
      let hours = Int(seconds / 3600)
      let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
      let secs = Int(seconds.truncatingRemainder(dividingBy: 60))

      if hours > 0 {
        return String(format: "[%02d:%02d:%02d]", hours, minutes, secs)
      } else {
        return String(format: "[%02d:%02d]", minutes, secs)
      }

    case .seconds:
      return String(format: "[%.1fs]", seconds)

    case .none:
      return ""
    }
  }
}

// MARK: - Formatter Factory

struct TranscriptFormatterFactory {
  static func formatter(for format: TranscriptFormat, includeTimestamps: Bool = false)
    -> TranscriptFormatter
  {
    switch format {
    case .srt:
      return SRTFormatter()
    case .txt:
      var txtFormatter = PlainTextFormatter()
      txtFormatter.includeTimestamps = includeTimestamps
      txtFormatter.timestampFormat = includeTimestamps ? .readable : .none
      return txtFormatter
    }
  }
}
