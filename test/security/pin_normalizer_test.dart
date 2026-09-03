import 'dart:convert';
import 'package:api_client/api_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinNormalizer', () {
    final rawBytes = List<int>.generate(32, (i) => i);
    final digest = sha256.convert(rawBytes);
    final hexDigest = digest.toString().toLowerCase(); // 64-char hex
    final base64Digest = base64.encode(digest.bytes); // 44-char base64

    test('parses plain 64-char hex correctly', () {
      final pin = PinNormalizer.parse(hexDigest);
      expect(pin.type, PinType.anySha256);
      expect(pin.hexValue, hexDigest);
      expect(pin.base64Value, base64Digest);
      expect(
        pin.matches(
          certSha256Hex: hexDigest,
          certSha256Base64: base64Digest,
        ),
        isTrue,
      );
    });

    test('parses uppercase colon-separated hex correctly', () {
      final colonHex = hexDigest
          .toUpperCase()
          .replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)}:')
          .substring(0, hexDigest.length + (hexDigest.length ~/ 2) - 1);

      final pin = PinNormalizer.parse(colonHex);
      expect(pin.type, PinType.anySha256);
      expect(pin.hexValue, hexDigest);
      expect(pin.base64Value, base64Digest);
    });

    test('parses space-separated hex correctly', () {
      final spaceHex = hexDigest
          .toUpperCase()
          .replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)} ')
          .trim();

      final pin = PinNormalizer.parse(spaceHex);
      expect(pin.hexValue, hexDigest);
    });

    test('parses sha256/base64 pin format', () {
      final pinString = 'sha256/$base64Digest';
      final pin = PinNormalizer.parse(pinString);
      expect(pin.type, PinType.anySha256);
      expect(pin.hexValue, hexDigest);
      expect(pin.base64Value, base64Digest);
      expect(
        pin.matches(
          certSha256Hex: hexDigest,
          certSha256Base64: base64Digest,
        ),
        isTrue,
      );
    });

    test('parses spki/sha256/base64 pin format', () {
      final pinString = 'spki/sha256/$base64Digest';
      final pin = PinNormalizer.parse(pinString);
      expect(pin.type, PinType.spkiSha256);
      expect(pin.hexValue, hexDigest);
      expect(pin.base64Value, base64Digest);

      // Matches SPKI, but not Cert
      expect(
        pin.matches(
          certSha256Hex: 'different_hash',
          spkiSha256Hex: hexDigest,
          spkiSha256Base64: base64Digest,
        ),
        isTrue,
      );
      expect(
        pin.matches(
          certSha256Hex: hexDigest,
          spkiSha256Hex: 'different_hash',
        ),
        isFalse,
      );
    });

    test('parses cert/sha256/base64 pin format', () {
      final pinString = 'cert/sha256/$base64Digest';
      final pin = PinNormalizer.parse(pinString);
      expect(pin.type, PinType.certSha256);
      expect(pin.hexValue, hexDigest);

      // Matches Cert, but not SPKI
      expect(
        pin.matches(
          certSha256Hex: hexDigest,
          spkiSha256Hex: 'other',
        ),
        isTrue,
      );
      expect(
        pin.matches(
          certSha256Hex: 'other',
          spkiSha256Hex: hexDigest,
        ),
        isFalse,
      );
    });

    test('parses RFC 7469 pin-sha256="..." header format', () {
      final pinString = 'pin-sha256="$base64Digest"';
      final pin = PinNormalizer.parse(pinString);
      expect(pin.type, PinType.spkiSha256);
      expect(pin.hexValue, hexDigest);
      expect(pin.base64Value, base64Digest);
    });

    test('parses SHA-1 40-char hex pin format', () {
      final sha1Digest = sha1.convert(rawBytes).toString().toLowerCase();
      final pinString = 'sha1:$sha1Digest';
      final pin = PinNormalizer.parse(pinString);
      expect(pin.type, PinType.certSha1);
      expect(pin.hexValue, sha1Digest);
      expect(
        pin.matches(
          certSha256Hex: 'any',
          certSha1Hex: sha1Digest,
        ),
        isTrue,
      );
    });
  });
}
