import 'package:flutter/foundation.dart';

/// Callback invoked when a custom certificate validation logic is required.
///
/// Return `true` if the certificate is accepted, `false` to reject the connection.
typedef CertificateCustomValidator = bool Function(
  dynamic cert,
  String host,
  int port,
);

/// Callback invoked when certificate pinning verification fails.
typedef OnPinningFailureCallback = void Function(
  CertificatePinningFailure failure,
);

/// Configuration for SSL / TLS Certificate and Public Key (SPKI) Pinning.
@immutable
class CertificatePinningConfig {
  /// Whether certificate pinning is active. Defaults to `true`.
  final bool enabled;

  /// Map of host patterns (e.g. `'api.example.com'`, `'*.example.com'`, or `'*'`)
  /// to a list of allowed pin strings.
  ///
  /// Supported pin formats:
  /// - **SHA-256 Certificate Fingerprint (Hex)**:
  ///   `'2B:3C:4D:5E:...'` or `'2b3c4d5e...'`
  /// - **SHA-256 Certificate Fingerprint (Base64)**:
  ///   `'sha256/WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys='`
  /// - **SPKI Public Key Pin (Base64 / RFC 7469)**:
  ///   `'spki/sha256/WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys='` or
  ///   `'sha256/WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys='`
  /// - **SPKI Public Key Pin (Hex)**:
  ///   `'spki:2b:3c:4d:...'` or `'spki:2b3c4d...'`
  /// - **SHA-1 Certificate Fingerprint (Hex)**:
  ///   `'sha1:2B:3C:...'` or `'2B:3C:...'` (when 20 bytes long)
  final Map<String, List<String>> allowedPins;

  /// Custom trusted certificates to include in the TLS [SecurityContext].
  ///
  /// Each item can be:
  /// - A [String] containing PEM-encoded certificate text (`-----BEGIN CERTIFICATE-----...`)
  /// - A [String] containing an absolute or relative file path to a `.pem`/`.crt`/`.der` file
  /// - A [List<int>] or `Uint8List` containing raw DER or UTF-8 PEM bytes
  final List<dynamic> trustedCertificates;

  /// Whether to retain default system root CAs in addition to [trustedCertificates].
  ///
  /// Defaults to `true`. When set to `false`, ONLY certificates explicitly listed in
  /// [trustedCertificates] will be trusted by the underlying TLS engine.
  final bool includeDefaultTrustedRoots;

  /// If `true`, validation failures will be logged as warnings and trigger
  /// [onPinningFailure], but the TLS connection will NOT be blocked.
  ///
  /// This is useful for monitoring, telemetry, or rollout phases without risking
  /// breaking production user traffic. Defaults to `false` (strict enforcement).
  final bool reportOnly;

  /// If `true`, certificate pinning is bypassed when running in debug mode ([kDebugMode]).
  ///
  /// Useful for local development and proxy debugging (e.g. Charles, Proxyman).
  /// Defaults to `false`.
  final bool bypassInDebug;

  /// An optional custom validator callback for fine-grained certificate validation.
  ///
  /// When provided, this callback is evaluated alongside pin matching.
  final CertificateCustomValidator? customValidator;

  /// Callback triggered whenever certificate pinning verification fails.
  final OnPinningFailureCallback? onPinningFailure;

  const CertificatePinningConfig({
    this.enabled = true,
    this.allowedPins = const {},
    this.trustedCertificates = const [],
    this.includeDefaultTrustedRoots = true,
    this.reportOnly = false,
    this.bypassInDebug = false,
    this.customValidator,
    this.onPinningFailure,
  });

  /// Whether any pins or trusted certificates are configured.
  bool get hasRules =>
      allowedPins.isNotEmpty ||
      trustedCertificates.isNotEmpty ||
      customValidator != null;

  /// Creates a copy of this configuration with the given fields replaced.
  CertificatePinningConfig copyWith({
    bool? enabled,
    Map<String, List<String>>? allowedPins,
    List<dynamic>? trustedCertificates,
    bool? includeDefaultTrustedRoots,
    bool? reportOnly,
    bool? bypassInDebug,
    CertificateCustomValidator? customValidator,
    OnPinningFailureCallback? onPinningFailure,
  }) {
    return CertificatePinningConfig(
      enabled: enabled ?? this.enabled,
      allowedPins: allowedPins ?? this.allowedPins,
      trustedCertificates: trustedCertificates ?? this.trustedCertificates,
      includeDefaultTrustedRoots:
          includeDefaultTrustedRoots ?? this.includeDefaultTrustedRoots,
      reportOnly: reportOnly ?? this.reportOnly,
      bypassInDebug: bypassInDebug ?? this.bypassInDebug,
      customValidator: customValidator ?? this.customValidator,
      onPinningFailure: onPinningFailure ?? this.onPinningFailure,
    );
  }
}

/// Represents the details of a certificate pinning verification failure.
class CertificatePinningFailure {
  /// The hostname requested.
  final String host;

  /// The port connected to.
  final int port;

  /// The Subject field of the presented certificate (if available).
  final String? certificateSubject;

  /// The Issuer field of the presented certificate (if available).
  final String? certificateIssuer;

  /// The SHA-256 fingerprint of the presented certificate (lowercase hex).
  final String sha256Fingerprint;

  /// The SHA-1 fingerprint of the presented certificate (lowercase hex), if available.
  final String? sha1Fingerprint;

  /// The SHA-256 hash of the SubjectPublicKeyInfo (SPKI) (lowercase hex).
  final String? spkiSha256Hex;

  /// The SHA-256 hash of the SubjectPublicKeyInfo (SPKI) (RFC 7469 base64 format).
  final String? spkiSha256Base64;

  /// The list of expected pins configured for this host.
  final List<String> expectedPins;

  /// Human-readable explanation of the failure.
  final String reason;

  /// Timestamp when the failure occurred.
  final DateTime timestamp;

  CertificatePinningFailure({
    required this.host,
    required this.port,
    this.certificateSubject,
    this.certificateIssuer,
    required this.sha256Fingerprint,
    this.sha1Fingerprint,
    this.spkiSha256Hex,
    this.spkiSha256Base64,
    required this.expectedPins,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'CertificatePinningFailure('
        'host: $host:$port, '
        'subject: $certificateSubject, '
        'issuer: $certificateIssuer, '
        'certSha256: $sha256Fingerprint, '
        'spkiSha256Base64: $spkiSha256Base64, '
        'expectedPins: $expectedPins, '
        'reason: $reason'
        ')';
  }
}

/// Exception thrown when SSL/TLS Certificate or SPKI Pinning validation fails in strict mode.
class CertificatePinningException implements Exception {
  /// Details of the pinning failure.
  final CertificatePinningFailure failure;

  /// Error message.
  final String message;

  CertificatePinningException(this.failure, [String? message])
      : message = message ??
            'SSL / TLS certificate pinning failed for host "${failure.host}:${failure.port}". '
            'Reason: ${failure.reason}';

  @override
  String toString() => 'CertificatePinningException: $message ($failure)';
}
