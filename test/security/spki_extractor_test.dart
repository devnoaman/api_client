import 'dart:convert';
import 'dart:typed_data';
import 'package:api_client/api_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpkiExtractor', () {
    test('extracts SubjectPublicKeyInfo from valid ASN.1 DER certificate', () {
      // Build a minimal valid ASN.1 DER certificate structure
      final spkiContent = [0x30, 0x04, 0xAA, 0xBB, 0xCC, 0xDD]; // SPKI SEQUENCE

      final tbsChildren = <int>[
        0xA0, 0x03, 0x02, 0x01, 0x02, // version v3
        0x02, 0x01, 0x42, // serialNumber
        0x30, 0x02, 0x05, 0x00, // signature algorithm
        0x30, 0x00, // issuer
        0x30, 0x00, // validity
        0x30, 0x00, // subject
        ...spkiContent, // subjectPublicKeyInfo
      ];

      final tbsSeq = [
        0x30,
        tbsChildren.length,
        ...tbsChildren,
      ];

      final certChildren = <int>[
        ...tbsSeq,
        0x30, 0x00, // signatureAlgorithm
        0x03, 0x02, 0x00, 0xFF, // signatureValue
      ];

      final certDer = Uint8List.fromList([
        0x30,
        certChildren.length,
        ...certChildren,
      ]);

      final spkiInfo = SpkiExtractor.extract(certDer);
      expect(spkiInfo, isNotNull);
      expect(spkiInfo!.spkiDerBytes, Uint8List.fromList(spkiContent));

      final expectedDigest = sha256.convert(spkiContent);
      expect(spkiInfo.sha256Hex, expectedDigest.toString().toLowerCase());
      expect(spkiInfo.sha256Base64, base64.encode(expectedDigest.bytes));
      expect(
        spkiInfo.rfc7469Pin,
        'sha256/${base64.encode(expectedDigest.bytes)}',
      );
    });

    test('returns null gracefully on empty or malformed DER bytes', () {
      expect(SpkiExtractor.extract(Uint8List(0)), isNull);
      expect(SpkiExtractor.extract(Uint8List.fromList([0x30, 0x01])), isNull);
      expect(
        SpkiExtractor.extract(Uint8List.fromList([0x02, 0x02, 0x01, 0x01])),
        isNull,
      );
    });
  });
}
