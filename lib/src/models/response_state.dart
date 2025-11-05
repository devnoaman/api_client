sealed class ResponseState {}

class Success extends ResponseState {
  final dynamic data;

  Success(this.data);
}

class Failed extends ResponseState {
  final Object error;
  final StackTrace? stackTrace;
  final Exception? exception;
  final dynamic data;

  Failed(
    this.error,
    this.stackTrace,
    this.exception,
    this.data,
  );
}
