/// Utility for matching hostname patterns against requested hostnames.
class HostMatcher {
  HostMatcher._();

  /// Normalizes a host string (converts to lowercase, removes port, strips leading/trailing slashes/whitespace).
  static String normalizeHost(String host) {
    var clean = host.trim().toLowerCase();

    // Strip scheme if present (e.g. https://)
    if (clean.contains('://')) {
      clean = clean.split('://').last;
    }

    // Strip path or query if present
    if (clean.contains('/')) {
      clean = clean.split('/').first;
    }

    // Strip port if present
    if (clean.contains(':')) {
      clean = clean.split(':').first;
    }

    return clean;
  }

  /// Checks if [host] matches the [pattern].
  ///
  /// Supported pattern formats:
  /// - Exact match: `'api.example.com'` matches `'api.example.com'`
  /// - Wildcard prefix: `'*.example.com'` matches `'api.example.com'`, `'sub.api.example.com'`
  /// - Catch-all wildcard: `'*'` matches any host
  static bool matches(String host, String pattern) {
    final cleanHost = normalizeHost(host);
    final cleanPattern = normalizeHost(pattern);

    if (cleanPattern == '*' || cleanPattern.isEmpty) {
      return true;
    }

    if (cleanPattern == cleanHost) {
      return true;
    }

    // Handle wildcard patterns like *.example.com or .example.com
    if (cleanPattern.startsWith('*.')) {
      final suffix = cleanPattern.substring(2); // 'example.com'
      return cleanHost == suffix || cleanHost.endsWith('.$suffix');
    }

    if (cleanPattern.startsWith('.')) {
      final suffix = cleanPattern.substring(1);
      return cleanHost == suffix || cleanHost.endsWith('.$suffix');
    }

    return false;
  }

  /// Finds all pin strings from [allowedPinsMap] that match the given [host].
  static List<String> findMatchingPins(
    String host,
    Map<String, List<String>> allowedPinsMap,
  ) {
    final cleanHost = normalizeHost(host);
    final matchedPins = <String>{};

    // 1. Exact matches first
    for (final entry in allowedPinsMap.entries) {
      final pattern = entry.key;
      if (normalizeHost(pattern) == cleanHost) {
        matchedPins.addAll(entry.value);
      }
    }

    // 2. Wildcard matches
    for (final entry in allowedPinsMap.entries) {
      final pattern = entry.key;
      final cleanPattern = normalizeHost(pattern);
      if (cleanPattern != cleanHost && matches(cleanHost, pattern)) {
        matchedPins.addAll(entry.value);
      }
    }

    return matchedPins.toList();
  }
}
