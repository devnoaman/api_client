/// Parallel to [ResponseState] for streaming endpoints.
///
/// Use with [BaseController.streamWithResult] and pattern-match in the UI:
/// ```dart
/// await for (final event in controller.streamWithResult()) {
///   switch (event) {
///     case StreamChunk(:final data, :final event): ...
///     case StreamDone(): ...
///     case StreamFailed(:final error): ...
///   }
/// }
/// ```
sealed class StreamResponseState<E> {}

/// A successfully decoded stream chunk.
final class StreamChunk<E> extends StreamResponseState<E> {
  final E data;

  /// SSE `event:` name (e.g. `meta`, `delta`, `part`, `done`), when present.
  final String? event;

  /// Optional SSE `id:` field.
  final String? id;

  StreamChunk(this.data, {this.event, this.id});
}

/// The upstream closed cleanly (after optional SSE `[DONE]`).
final class StreamDone<E> extends StreamResponseState<E> {
  /// Optional final payload if the server sent one before closing.
  final E? data;

  StreamDone([this.data]);
}

/// The stream failed before or while reading chunks.
final class StreamFailed<E> extends StreamResponseState<E> {
  final Object error;
  final StackTrace? stackTrace;
  final Exception? exception;
  final dynamic data;

  StreamFailed(
    this.error,
    this.stackTrace,
    this.exception,
    this.data,
  );
}
