import 'dart:convert';
import 'dart:typed_data';
import 'package:api_client/api_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper mock certificate holding DER bytes and metadata
class MockCertificate {
  final Uint8List der;
  final String subject;
  final String issuer;
  final Uint8List? sha1;

  MockCertificate({
    required this.der,
    this.subject = 'CN=api.example.com',
    this.issuer = 'CN=Example CA',
    this.sha1,
  });
}

void main() {
  group('CertificatePinningManager', () {
    // Generate sample DER certificate with SPKI
    final spkiContent = [0x30, 0x04, 0x01, 0x02, 0x03, 0x04];
    final tbsChildren = <int>[
      0xA0, 0x03, 0x02, 0x01, 0x02,
      0x02, 0x01, 0x01,
      0x30, 0x02, 0x05, 0x00,
      0x30, 0x00,
      0x30, 0x00,
      0x30, 0x00,
      ...spkiContent,
    ];
    final tbsSeq = [0x30, tbsChildren.length, ...tbsChildren];
    final certChildren = <int>[
      ...tbsSeq,
      0x30, 0x00,
      0x03, 0x02, 0x00, 0xAA,
    ];
    final certDer = Uint8List.fromList([
      0x30,
      certChildren.length,
      ...certChildren,
    ]);

    final certSha256Digest = sha256.convert(certDer);
    final certSha256Hex = certSha256Digest.toString().toLowerCase();
    final certSha256Base64 = base64.encode(certSha256Digest.bytes);

    final spkiSha256Digest = sha256.convert(spkiContent);
    final spkiSha256Base64 = base64.encode(spkiSha256Digest.bytes);

    test('accepts certificate when SHA-256 fingerprint matches', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': [
            certSha256Hex, // hex match
          ],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isTrue);
    });

    test('accepts certificate when base64 sha256/ fingerprint matches', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': [
            'sha256/$certSha256Base64',
          ],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isTrue);
    });

    test('accepts certificate when SPKI pin matches', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          '*.example.com': [
            'spki/sha256/$spkiSha256Base64',
          ],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isTrue);
    });

    test('accepts certificate when any backup pin matches', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': [
            'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // expired/old pin
            'sha256/$certSha256Base64', // valid backup pin
          ],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      expect(
        manager.validate(cert: cert, host: 'api.example.com', port: 443),
        isTrue,
      );
    });

    test('rejects connection and calls onPinningFailure when pin mismatches in strict mode', () {
      CertificatePinningFailure? capturedFailure;

      final config = CertificatePinningConfig(
        enabled: true,
        reportOnly: false,
        allowedPins: {
          'api.example.com': [
            'sha256/WRONGPINWRONGPINWRONGPINWRONGPINWRONGPINWR=',
          ],
        },
        onPinningFailure: (failure) {
          capturedFailure = failure;
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isFalse);
      expect(capturedFailure, isNotNull);
      expect(capturedFailure!.host, 'api.example.com');
      expect(capturedFailure!.port, 443);
      expect(capturedFailure!.sha256Fingerprint, certSha256Hex);
      expect(capturedFailure!.reason, contains('does not match'));
    });

    test('allows connection in reportOnly mode even when pin mismatches', () {
      CertificatePinningFailure? capturedFailure;

      final config = CertificatePinningConfig(
        enabled: true,
        reportOnly: true,
        allowedPins: {
          'api.example.com': [
            'sha256/WRONGPINWRONGPINWRONGPINWRONGPINWRONGPINWR=',
          ],
        },
        onPinningFailure: (failure) {
          capturedFailure = failure;
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isTrue); // Allowed because reportOnly is true
      expect(capturedFailure, isNotNull);
    });

    test('allows unpinned hosts by default', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': ['sha256/some_pin'],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      // other.org is not in allowedPins
      final result = manager.validate(
        cert: cert,
        host: 'other.org',
        port: 443,
      );

      expect(result, isTrue);
    });

    test('evaluates customValidator callback', () {
      var customValidatorCalled = false;

      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': [certSha256Hex],
        },
        customValidator: (cert, host, port) {
          customValidatorCalled = true;
          return host == 'api.example.com';
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isTrue);
      expect(customValidatorCalled, isTrue);
    });

    test('customValidator can reject connection even if pin matches', () {
      final config = CertificatePinningConfig(
        enabled: true,
        allowedPins: {
          'api.example.com': [certSha256Hex],
        },
        customValidator: (cert, host, port) => false,
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      final result = manager.validate(
        cert: cert,
        host: 'api.example.com',
        port: 443,
      );

      expect(result, isFalse);
    });

    test('bypasses validation when enabled is false', () {
      final config = CertificatePinningConfig(
        enabled: false,
        allowedPins: {
          'api.example.com': ['sha256/WRONGPIN='],
        },
      );

      final manager = CertificatePinningManager(config);
      final cert = MockCertificate(der: certDer);

      expect(
        manager.validate(cert: cert, host: 'api.example.com', port: 443),
        isTrue,
      );
    });
  });
}
