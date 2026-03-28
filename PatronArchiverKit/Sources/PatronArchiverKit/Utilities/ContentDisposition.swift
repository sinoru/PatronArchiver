import RawStructuredFieldValues

/// Parses a Content-Disposition header value (RFC 6266).
///
/// Uses RFC 9651 structured field parsing for parameter extraction
/// (semicolon splitting, quoted-string handling), then applies
/// RFC 5987 ext-value decoding for `filename*` parameters.
struct ContentDisposition {
    /// The disposition type, e.g. `"attachment"` or `"inline"`.
    let type: String

    /// The resolved filename.
    ///
    /// Per RFC 6266 §4.3, `filename*` takes precedence over `filename`
    /// when both are present.
    let filename: String?

    /// Parses a Content-Disposition header value.
    ///
    /// - Parameter headerValue: The raw header value,
    ///   e.g. `attachment; filename="report.pdf"`.
    /// - Returns: `nil` if parsing fails.
    init?(headerValue: String) {
        var parser = StructuredFieldValueParser(
            Array(headerValue.utf8)
        )
        guard let item = try? parser.parseItemFieldValue() else {
            return nil
        }

        guard case .token(let dispositionType) = item.rfc9651BareItem else {
            return nil
        }
        self.type = dispositionType

        // RFC 6266 §4.3: filename* takes precedence over filename
        if let starValue = item.rfc9651Parameters["filename*"],
           case .token(let extValue) = starValue,
           let decoded = Self.decodeRFC5987ExtValue(extValue) {
            self.filename = decoded
        } else if let plainValue = item.rfc9651Parameters["filename"],
                  case .string(let name) = plainValue {
            self.filename = name
        } else {
            self.filename = nil
        }
    }

    /// Decodes an RFC 5987 ext-value: `charset'language'percent-encoded`.
    ///
    /// Only UTF-8 charset is supported. The language tag is ignored
    /// per the RFC.
    private static func decodeRFC5987ExtValue(_ extValue: String) -> String? {
        let parts = extValue.split(
            separator: "'",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard parts.count == 3 else { return nil }

        let charset = parts[0].lowercased()
        guard charset == "utf-8" else { return nil }

        return String(parts[2]).removingPercentEncoding
    }
}
