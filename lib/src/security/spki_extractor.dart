import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Extracted SubjectPublicKeyInfo (SPKI) information.
class SpkiInfo {
  /// Raw SubjectPublicKeyInfo DER bytes (including tag, length, and value).
  final Uint8List spkiDerBytes;

  /// SHA-256 hash in lowercase hex format (64 characters).
  final String sha256Hex;

  /// SHA-256 hash in Base64 format (44 characters, e.g. `"WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys="`).
  final String sha256Base64;

  /// RFC 7469 standard pin representation (e.g. `"sha256/WoiWRyIOVNa9ihaapVIysOooiWRyIOVNa9ihaapVIys="`).
  String get rfc7469Pin => 'sha256/$sha256Base64';

  const SpkiInfo({
    required this.spkiDerBytes,
    required this.sha256Hex,
    required this.sha256Base64,
  });

  @override
  String toString() => 'SpkiInfo(sha256Hex: $sha256Hex, sha256Base64: $sha256Base64)';
}

/// Utility to parse X.509 DER certificates and extract the SubjectPublicKeyInfo (SPKI).
class SpkiExtractor {
  SpkiExtractor._();

  /// Extracts the SubjectPublicKeyInfo (SPKI) structure from X.509 DER bytes
  /// and computes its SHA-256 digest in hex and base64 formats.
  ///
  /// Returns `null` if the certificate structure cannot be parsed.
  static SpkiInfo? extract(Uint8List derBytes) {
    try {
      final spkiBytes = _extractSpkiBytes(derBytes);
      if (spkiBytes == null || spkiBytes.isEmpty) return null;

      final digest = sha256.convert(spkiBytes);
      final hex = digest.toString().toLowerCase();
      final b64 = base64.encode(digest.bytes);

      return SpkiInfo(
        spkiDerBytes: spkiBytes,
        sha256Hex: hex,
        sha256Base64: b64,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses the ASN.1 DER structure to locate the `subjectPublicKeyInfo` sequence.
  static Uint8List? _extractSpkiBytes(Uint8List bytes) {
    var offset = 0;

    // 1. Root Certificate SEQUENCE (tag 0x30)
    final certHeader = _readHeader(bytes, offset);
    if (certHeader == null || certHeader.tag != 0x30) return null;
    offset = certHeader.valueOffset;

    // 2. tbsCertificate SEQUENCE (tag 0x30)
    final tbsHeader = _readHeader(bytes, offset);
    if (tbsHeader == null || tbsHeader.tag != 0x30) return null;

    final tbsEnd = tbsHeader.valueOffset + tbsHeader.length;
    offset = tbsHeader.valueOffset;

    // 3. Inside tbsCertificate:
    // Child 0: Version [0] (tag 0xA0) - OPTIONAL in X.509
    if (offset < tbsEnd && bytes[offset] == 0xA0) {
      final vHeader = _readHeader(bytes, offset);
      if (vHeader == null) return null;
      offset = vHeader.valueOffset + vHeader.length;
    }

    // Child 1: serialNumber (INTEGER, tag 0x02)
    final snHeader = _readHeader(bytes, offset);
    if (snHeader == null || snHeader.tag != 0x02) return null;
    offset = snHeader.valueOffset + snHeader.length;

    // Child 2: signature (AlgorithmIdentifier SEQUENCE, tag 0x30)
    final sigHeader = _readHeader(bytes, offset);
    if (sigHeader == null || sigHeader.tag != 0x30) return null;
    offset = sigHeader.valueOffset + sigHeader.length;

    // Child 3: issuer (Name SEQUENCE, tag 0x30)
    final issuerHeader = _readHeader(bytes, offset);
    if (issuerHeader == null || issuerHeader.tag != 0x30) return null;
    offset = issuerHeader.valueOffset + issuerHeader.length;

    // Child 4: validity (Validity SEQUENCE, tag 0x30)
    final valHeader = _readHeader(bytes, offset);
    if (valHeader == null || valHeader.tag != 0x30) return null;
    offset = valHeader.valueOffset + valHeader.length;

    // Child 5: subject (Name SEQUENCE, tag 0x30)
    final subjHeader = _readHeader(bytes, offset);
    if (subjHeader == null || subjHeader.tag != 0x30) return null;
    offset = subjHeader.valueOffset + subjHeader.length;

    // Child 6: subjectPublicKeyInfo (SubjectPublicKeyInfo SEQUENCE, tag 0x30)
    final spkiHeader = _readHeader(bytes, offset);
    if (spkiHeader == null || spkiHeader.tag != 0x30) return null;

    final spkiTotalLength = (spkiHeader.valueOffset - offset) + spkiHeader.length;
    if (offset + spkiTotalLength > bytes.length) return null;

    return bytes.sublist(offset, offset + spkiTotalLength);
  }

  static _Asn1Header? _readHeader(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return null;

    final tag = bytes[offset];
    var cursor = offset + 1;
    if (cursor >= bytes.length) return null;

    final firstLenByte = bytes[cursor];
    cursor++;

    int length;
    if (firstLenByte < 0x80) {
      length = firstLenByte;
    } else {
      final numOctets = firstLenByte & 0x7F;
      if (numOctets == 0 || cursor + numOctets > bytes.length) return null;

      length = 0;
      for (var i = 0; i < numOctets; i++) {
        length = (length << 8) | bytes[cursor++];
      }
    }

    return _Asn1Header(tag: tag, length: length, valueOffset: cursor);
  }
}

class _Asn1Header {
  final int tag;
  final int length;
  final int valueOffset;

  const _Asn1Header({
    required this.tag,
    required this.length,
    required this.valueOffset,
  });
}
