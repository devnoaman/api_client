import 'dart:convert';
import 'dart:typed_data';

/// The target type of a cryptographic pin.
enum PinType {
  /// The SHA-256 fingerprint of the full X.509 certificate DER bytes.
  certSha256,

  /// The SHA-1 fingerprint of the full X.509 certificate DER bytes.
  certSha1,

  /// The SHA-256 hash of the SubjectPublicKeyInfo (SPKI) sequence bytes.
  spkiSha256,

  /// Matches either the certificate SHA-256 fingerprint OR the SPKI SHA-256 hash.
  anySha256,
}

/// A parsed and normalized cryptographic pin.
class NormalizedPin {
  /// The type of pin.
  final PinType type;

  /// Lowercase hex string of the digest (64 chars for SHA-256, 40 chars for SHA-1).
  final String hexValue;

  /// Standard base64 representation of the digest (if SHA-256).
  final String? base64Value;

  /// Original string passed in configuration.
  final String raw;

  const NormalizedPin({
    required this.type,
    required this.hexValue,
    this.base64Value,
    required this.raw,
  });

  /// Evaluates whether this pin matches the given presented certificate digests.
  bool matches({
    required String certSha256Hex,
    String? certSha1Hex,
    String? spkiSha256Hex,
    String? certSha256Base64,
    String? spkiSha256Base64,
  }) {
    final cleanCertHex = certSha256Hex.toLowerCase();
    final cleanCertSha1 = certSha1Hex?.toLowerCase();
    final cleanSpkiHex = spkiSha256Hex?.toLowerCase();

    switch (type) {
      case PinType.certSha256:
        return hexValue == cleanCertHex ||
            (base64Value != null && base64Value == certSha256Base64);

      case PinType.certSha1:
        return cleanCertSha1 != null && hexValue == cleanCertSha1;

      case PinType.spkiSha256:
        return (cleanSpkiHex != null && hexValue == cleanSpkiHex) ||
            (base64Value != null &&
                spkiSha256Base64 != null &&
                base64Value == spkiSha256Base64);

      case PinType.anySha256:
        final matchesCert = hexValue == cleanCertHex ||
            (base64Value != null && base64Value == certSha256Base64);
        final matchesSpki = (cleanSpkiHex != null && hexValue == cleanSpkiHex) ||
            (base64Value != null &&
                spkiSha256Base64 != null &&
                base64Value == spkiSha256Base64);
        return matchesCert || matchesSpki;
    }
  }

  @override
  String toString() => 'NormalizedPin($type: $hexValue (raw: "$raw"))';
}

/// Utility for normalizing various pin and fingerprint input string formats.
class PinNormalizer {
  PinNormalizer._();

  /// Parses and normalizes a pin string into a [NormalizedPin].
  ///
  /// Supports:
  /// - Hex with colons: `'AA:BB:CC:...'`
  /// - Hex with spaces: `'AA BB CC ...'`
  /// - Plain hex: `'aabbcc...'`
  /// - Base64 SHA-256: `'sha256/WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys='`
  /// - SPKI Base64 / Hex: `'spki/sha256/...'`, `'spki:sha256:...'`, `'spki:2b:3c...'`
  /// - Cert Base64 / Hex: `'cert/sha256/...'`, `'cert:sha256:...'`, `'cert:2b:3c...'`
  /// - SHA-1: `'sha1:2b:3c...'` or 40-char hex
  static NormalizedPin parse(String pin) {
    var trimmed = pin.trim();

    // Strip quotes if present (e.g. pin-sha256="...")
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }

    // Check for explicit SPKI prefix
    if (trimmed.toLowerCase().startsWith('spki/') ||
        trimmed.toLowerCase().startsWith('spki:')) {
      final stripped = trimmed.substring(5).trim();
      return _parseDigest(stripped, defaultType: PinType.spkiSha256, raw: pin);
    }

    // Check for explicit Cert prefix
    if (trimmed.toLowerCase().startsWith('cert/') ||
        trimmed.toLowerCase().startsWith('cert:')) {
      final stripped = trimmed.substring(5).trim();
      return _parseDigest(stripped, defaultType: PinType.certSha256, raw: pin);
    }

    // Check for pin-sha256 prefix (RFC 7469)
    if (trimmed.toLowerCase().startsWith('pin-sha256=')) {
      final stripped = trimmed.substring(11).trim();
      return _parseDigest(stripped, defaultType: PinType.spkiSha256, raw: pin);
    }

    return _parseDigest(trimmed, defaultType: PinType.anySha256, raw: pin);
  }

  static NormalizedPin _parseDigest(
    String input, {
    required PinType defaultType,
    required String raw,
  }) {
    var clean = input.trim();
    if ((clean.startsWith('"') && clean.endsWith('"')) ||
        (clean.startsWith("'") && clean.endsWith("'"))) {
      if (clean.length >= 2) {
        clean = clean.substring(1, clean.length - 1).trim();
      }
    }

    // Handle sha1 prefix
    if (clean.toLowerCase().startsWith('sha1/') ||
        clean.toLowerCase().startsWith('sha1:')) {
      clean = clean.substring(5).trim();
      final hex = clean.replaceAll(':', '').replaceAll(' ', '').toLowerCase();
      return NormalizedPin(
        type: PinType.certSha1,
        hexValue: hex,
        raw: raw,
      );
    }

    // Handle sha256 prefix
    if (clean.toLowerCase().startsWith('sha256/') ||
        clean.toLowerCase().startsWith('sha256:')) {
      clean = clean.substring(7).trim();
    }

    // Check if it's base64 encoded (ends with '=' or length 44 without colons/spaces)
    if (clean.contains('/') || clean.contains('+') || clean.endsWith('=')) {
      try {
        final bytes = base64.decode(clean);
        if (bytes.length == 32) {
          final hex = _bytesToHex(bytes);
          final b64 = base64.encode(bytes);
          return NormalizedPin(
            type: defaultType,
            hexValue: hex,
            base64Value: b64,
            raw: raw,
          );
        }
      } catch (_) {
        // Fallthrough to hex parsing
      }
    }

    // Hex parsing: strip colons, dashes, and whitespace
    final strippedHex = clean
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toLowerCase();

    if (strippedHex.length == 64) {
      // 32-byte SHA-256
      final bytes = _hexToBytes(strippedHex);
      final b64 = bytes != null ? base64.encode(bytes) : null;
      return NormalizedPin(
        type: defaultType,
        hexValue: strippedHex,
        base64Value: b64,
        raw: raw,
      );
    } else if (strippedHex.length == 40) {
      // 20-byte SHA-1
      return NormalizedPin(
        type: PinType.certSha1,
        hexValue: strippedHex,
        raw: raw,
      );
    }

    // If 44 chars without standard base64 symbols, try base64 decode
    if (clean.length == 44) {
      try {
        final bytes = base64.decode(clean);
        if (bytes.length == 32) {
          final hex = _bytesToHex(bytes);
          return NormalizedPin(
            type: defaultType,
            hexValue: hex,
            base64Value: clean,
            raw: raw,
          );
        }
      } catch (_) {}
    }

    // Fallback as raw hex
    return NormalizedPin(
      type: defaultType,
      hexValue: strippedHex,
      raw: raw,
    );
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toLowerCase();
  }

  static Uint8List? _hexToBytes(String hex) {
    if (hex.length % 2 != 0) return null;
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      result[i ~/ 2] = byte;
    }
    return result;
  }
}
