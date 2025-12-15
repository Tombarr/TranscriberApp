import Foundation

// MARK: - Transcription Segment

/// Represents a single segment of transcribed audio with timing information
struct TranscriptionSegment {
  let text: String
  let timestamp: Double  // Start time in seconds
  let duration: Double  // Duration in seconds
}

// MARK: - SRT Formatter

/// Formats transcription segments into SubRip (SRT) subtitle format
struct SRTFormatter {

  /// Format a time value in seconds to SRT time format (HH:MM:SS,mmm)
  ///
  /// - Parameter seconds: Time value in seconds
  /// - Returns: Formatted time string in SRT format
  static func formatTime(_ seconds: Double) -> String {
    let hours = Int(seconds / 3600)
    let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
    let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
  }

  /// Generate SRT formatted content from transcription segments
  ///
  /// SRT format structure:
  /// ```
  /// 1
  /// 00:00:00,000 --> 00:00:02,000
  /// First subtitle text
  ///
  /// 2
  /// 00:00:02,000 --> 00:00:05,000
  /// Second subtitle text
  /// ```
  ///
  /// - Parameter segments: Array of transcription segments with timing information
  /// - Returns: Complete SRT formatted string
  static func generateSRT(from segments: [TranscriptionSegment]) -> String {
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

  /// Validate that an SRT file can be created from segments
  ///
  /// - Parameter segments: Array of transcription segments
  /// - Returns: True if segments are valid for SRT generation
  static func canGenerateSRT(from segments: [TranscriptionSegment]) -> Bool {
    guard !segments.isEmpty else { return false }

    // Check that all segments have valid timing
    for segment in segments {
      guard segment.timestamp >= 0 && segment.duration > 0 else {
        return false
      }
    }

    return true
  }
}
