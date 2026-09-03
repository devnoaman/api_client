import 'package:api_client/src/security/certificate_pinning_config.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:dio/dio.dart';

/// Fallback certificate pinning configuration for Web and non-IO platforms.
void setupCertificatePinning(Dio dio, CertificatePinningConfig config) {
  if (config.enabled && config.hasRules) {
    BaseLogger().info(
      'SSL/TLS certificate pinning is managed natively by the browser on Flutter Web.',
      name: 'CertificatePinning',
    );
  }
}
