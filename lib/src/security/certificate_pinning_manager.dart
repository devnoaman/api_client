import 'dart:convert';
import 'package:api_client/src/security/certificate_pinning_config.dart';
import 'package:api_client/src/security/host_matcher.dart';
import 'package:api_client/src/security/pin_normalizer.dart';
import 'package:api_client/src/security/spki_extractor.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Central engine for evaluating TLS certificates against pinning configuration.
class CertificatePinningManager {
  final CertificatePinningConfig config;
  final BaseLogger _logger;

  CertificatePinningManager(
    this.config, {
    BaseLogger? logger,
  }) : _logger = logger ?? BaseLogger();

  /// Validates a certificate presented by [host] on [port].
  ///
  /// The [cert] object can be an instance of `dart:io.X509Certificate`,
  /// a raw `Uint8List` DER byte array, or an object exposing `der` and `sha1` properties.
  ///
  /// Returns `true` if the certificate is accepted; `false` if rejected.
  bool validate({
    required dynamic cert,
    required String host,
    required int port,
  }) {
    // 1. Check if pinning is disabled
    if (!config.enabled) {
      return true;
    }

    // 2. Check if bypassed in debug mode
    if (config.bypassInDebug && kDebugMode) {
      _logger.debug(
        'SSL Pinning bypassed for "$host:$port" because bypassInDebug is enabled.',
        name: 'CertificatePinning',
      );
      return true;
    }

    // 3. Extract DER bytes and metadata from certificate
    final Uint8List? derBytes = _extractDerBytes(cert);
    if (derBytes == null || derBytes.isEmpty) {
      final failure = CertificatePinningFailure(
        host: host,
        port: port,
        sha256Fingerprint: '',
        expectedPins: HostMatcher.findMatchingPins(host, config.allowedPins),
        reason: 'Unable to extract DER bytes from certificate object ($cert).',
      );
      _handleFailure(failure);
      return config.reportOnly;
    }

    final String? subject = _extractSubject(cert);
    final String? issuer = _extractIssuer(cert);

    // Compute certificate SHA-256 fingerprint
    final certSha256Digest = sha256.convert(derBytes);
    final certSha256Hex = certSha256Digest.toString().toLowerCase();
    final certSha256Base64 = base64.encode(certSha256Digest.bytes);

    // Compute certificate SHA-1 fingerprint
    final certSha1Hex = _extractSha1Hex(cert, derBytes);

    // Extract SubjectPublicKeyInfo (SPKI)
    final spkiInfo = SpkiExtractor.extract(derBytes);

    // 4. Find configured pins for this host
    final expectedPinStrings =
        HostMatcher.findMatchingPins(host, config.allowedPins);

    // 5. If no pins are configured for this host:
    if (expectedPinStrings.isEmpty) {
      // Evaluate custom validator if provided
      if (config.customValidator != null) {
        final passed = config.customValidator!(cert, host, port);
        if (!passed) {
          final failure = CertificatePinningFailure(
            host: host,
            port: port,
            certificateSubject: subject,
            certificateIssuer: issuer,
            sha256Fingerprint: certSha256Hex,
            sha1Fingerprint: certSha1Hex,
            spkiSha256Hex: spkiInfo?.sha256Hex,
            spkiSha256Base64: spkiInfo?.sha256Base64,
            expectedPins: const [],
            reason: 'Custom validator rejected the certificate for "$host".',
          );
          _handleFailure(failure);
          return config.reportOnly;
        }
      }
      // Host is unpinned -> accept
      return true;
    }

    // 6. Match against expected pins
    final normalizedPins = expectedPinStrings.map(PinNormalizer.parse).toList();
    final matchedPin = normalizedPins.cast<NormalizedPin?>().firstWhere(
          (pin) => pin!.matches(
            certSha256Hex: certSha256Hex,
            certSha1Hex: certSha1Hex,
            spkiSha256Hex: spkiInfo?.sha256Hex,
            certSha256Base64: certSha256Base64,
            spkiSha256Base64: spkiInfo?.sha256Base64,
          ),
          orElse: () => null,
        );

    if (matchedPin == null) {
      final failure = CertificatePinningFailure(
        host: host,
        port: port,
        certificateSubject: subject,
        certificateIssuer: issuer,
        sha256Fingerprint: certSha256Hex,
        sha1Fingerprint: certSha1Hex,
        spkiSha256Hex: spkiInfo?.sha256Hex,
        spkiSha256Base64: spkiInfo?.sha256Base64,
        expectedPins: expectedPinStrings,
        reason:
            'Presented certificate does not match any of the ${expectedPinStrings.length} expected pin(s). '
            '[Cert SHA-256: $certSha256Hex | SPKI: ${spkiInfo?.rfc7469Pin ?? "N/A"}]',
      );
      _handleFailure(failure);
      return config.reportOnly;
    }

    // 7. Check custom validator if configured alongside pins
    if (config.customValidator != null) {
      final passed = config.customValidator!(cert, host, port);
      if (!passed) {
        final failure = CertificatePinningFailure(
          host: host,
          port: port,
          certificateSubject: subject,
          certificateIssuer: issuer,
          sha256Fingerprint: certSha256Hex,
          sha1Fingerprint: certSha1Hex,
          spkiSha256Hex: spkiInfo?.sha256Hex,
          spkiSha256Base64: spkiInfo?.sha256Base64,
          expectedPins: expectedPinStrings,
          reason:
              'Pin matched ($matchedPin) but custom validator rejected certificate for "$host".',
        );
        _handleFailure(failure);
        return config.reportOnly;
      }
    }

    _logger.debug(
      'SSL Pinning verified successfully for "$host:$port" using pin: ${matchedPin.raw}',
      name: 'CertificatePinning',
    );
    return true;
  }

  void _handleFailure(CertificatePinningFailure failure) {
    if (config.reportOnly) {
      _logger.warn(
        '[REPORT-ONLY] SSL Pinning failure for "${failure.host}:${failure.port}": ${failure.reason}',
        name: 'CertificatePinning',
      );
    } else {
      _logger.error(
        'SSL Pinning REJECTED connection to "${failure.host}:${failure.port}": ${failure.reason}',
        name: 'CertificatePinning',
      );
    }

    try {
      config.onPinningFailure?.call(failure);
    } catch (e, st) {
      _logger.error(
        'Exception in onPinningFailure callback: $e',
        st: st,
        name: 'CertificatePinning',
      );
    }
  }

  static Uint8List? _extractDerBytes(dynamic cert) {
    if (cert == null) return null;
    if (cert is Uint8List) return cert;
    if (cert is List<int>) return Uint8List.fromList(cert);

    try {
      // dart:io X509Certificate has .der
      final dynamic der = cert.der;
      if (der is Uint8List) return der;
      if (der is List<int>) return Uint8List.fromList(der);
    } catch (_) {}

    return null;
  }

  static String? _extractSubject(dynamic cert) {
    try {
      final dynamic subject = cert.subject;
      return subject?.toString();
    } catch (_) {
      return null;
    }
  }

  static String? _extractIssuer(dynamic cert) {
    try {
      final dynamic issuer = cert.issuer;
      return issuer?.toString();
    } catch (_) {
      return null;
    }
  }

  static String? _extractSha1Hex(dynamic cert, Uint8List derBytes) {
    try {
      final dynamic sha1Field = cert.sha1;
      if (sha1Field is Uint8List || sha1Field is List<int>) {
        return _bytesToHex(sha1Field as List<int>);
      }
    } catch (_) {}

    final digest = sha1.convert(derBytes);
    return digest.toString().toLowerCase();
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toLowerCase();
  }
}
