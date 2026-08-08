/// Base class for app-level exceptions. Lets callers catch the whole family
/// without catching everything.
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Storage / DB failures.
class StorageException extends AppException {
  const StorageException(super.message);
}

/// ML pipeline failures (embedding, captioning, matching).
class MlException extends AppException {
  const MlException(super.message);
}

/// Bad user input or invalid state from the UI layer.
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// File system or platform integration failure.
class PlatformException extends AppException {
  const PlatformException(super.message);
}
