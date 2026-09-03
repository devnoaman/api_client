import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:api_client/src/security/certificate_pinning_config.dart';
import 'package:api_client/src/security/certificate_pinning_manager.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Configures SSL/TLS Certificate Pinning on IO platforms (iOS, Android, macOS, Linux, Windows).
void setupCertificatePinning(Dio dio, CertificatePinningConfig config) {
  if (!config.enabled && !config.hasRules) {
    return;
  }

  final manager = CertificatePinningManager(config);
  final logger = BaseLogger();

  // 1. Configure SecurityContext if custom trusted certificates are supplied
  //    or if default trusted roots are disabled.
  SecurityContext? securityContext;
  if (config.trustedCertificates.isNotEmpty ||
      !config.includeDefaultTrustedRoots) {
    securityContext = SecurityContext(
      withTrustedRoots: config.includeDefaultTrustedRoots,
    );

    for (final cert in config.trustedCertificates) {
      try {
        if (cert is Uint8List) {
          securityContext.setTrustedCertificatesBytes(cert);
        } else if (cert is List<int>) {
          securityContext.setTrustedCertificatesBytes(
            Uint8List.fromList(cert),
          );
        } else if (cert is String) {
          if (cert.trim().contains('BEGIN CERTIFICATE')) {
            securityContext.setTrustedCertificatesBytes(
              Uint8List.fromList(utf8.encode(cert)),
            );
          } else {
            // Assume file path
            securityContext.setTrustedCertificates(cert);
          }
        }
      } catch (e, st) {
        logger.error(
          'Failed to load trusted certificate into SecurityContext ($cert): $e',
          st: st,
          name: 'CertificatePinning',
        );
      }
    }
  }

  // 2. Configure IOHttpClientAdapter with both badCertificateCallback and validateCertificate
  final adapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient(context: securityContext);
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        return manager.validate(cert: cert, host: host, port: port);
      };
      return client;
    },
    validateCertificate: (X509Certificate? cert, String host, int port) {
      if (cert == null) return false;
      return manager.validate(cert: cert, host: host, port: port);
    },
  );

  dio.httpClientAdapter = adapter;
  logger.info(
    'SSL/TLS Certificate Pinning initialized (${config.allowedPins.length} host pattern(s), ${config.trustedCertificates.length} trusted cert(s)).',
    name: 'CertificatePinning',
  );
}
