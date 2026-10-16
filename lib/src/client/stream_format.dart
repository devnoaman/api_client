/// Wire format for HTTP response-body streaming (AI agent messages, etc.).
enum StreamFormat {
  /// Server-Sent Events (`text/event-stream`). Parses `data:` fields;
  /// ignores `[DONE]`.
  sse,

  /// Newline-delimited JSON (`application/x-ndjson`). One JSON object per line.
  ndjson,
}

extension StreamFormatAccept on StreamFormat {
  /// Prefer `Accept` header value for this format.
  String get acceptHeader => switch (this) {
        StreamFormat.sse => 'text/event-stream',
        StreamFormat.ndjson => 'application/x-ndjson',
      };
}
