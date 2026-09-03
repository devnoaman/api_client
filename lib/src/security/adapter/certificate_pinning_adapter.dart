import 'package:api_client/src/security/certificate_pinning_config.dart';
import 'package:dio/dio.dart';

import 'certificate_pinning_adapter_stub.dart'
    if (dart.library.io) 'certificate_pinning_adapter_io.dart' as impl;

/// Configures SSL / TLS Certificate and Public Key Pinning on the given [dio] instance.
void setupCertificatePinning(Dio dio, CertificatePinningConfig config) {
  impl.setupCertificatePinning(dio, config);
}
