/// Enumeration of HTTP methods for API requests.
enum HTTPMethod { get, post, delete, put, patch }

/// Extension to convert [HTTPMethod] enum values to their string representations.
extension HTTPMethodString on HTTPMethod {
  String get toStringName {
    switch (this) {
      case HTTPMethod.get:
        return "get";
      case HTTPMethod.post:
        return "post";
      case HTTPMethod.delete:
        return "delete";
      case HTTPMethod.patch:
        return "patch";
      case HTTPMethod.put:
        return "put";
    }
  }
}
