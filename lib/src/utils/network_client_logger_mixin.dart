// lib/auth/auth_interceptor.dart

import 'dart:convert';
import 'package:api_client/src/utils/auth_interceptor.dart';
import 'package:api_client/src/utils/base_logger.dart';
import 'package:colorize/colorize.dart';
import 'package:dio/dio.dart';

enum BodyType {
  formData,
  file,
  json,
}

mixin NetworkClientLoggerMixin {
  static const Styles defaultRequestStyle = Styles.YELLOW;
  static const Styles defaultResponseStyle = Styles.GREEN;
  static const Styles defaultErrorStyle = Styles.RED;
  final logger = BaseLogger();

  final _jsonEncoder = const JsonEncoder.withIndent('  ');
  void logRequest(
    RequestOptions options,
  ) {
    log(
      key: 'Request',
      value: '-> ${options.uri.toString()}',
      style: defaultRequestStyle,
    );
    log(
      key: 'Method',
      value: '-> ${options.method}',
      style: defaultRequestStyle,
    );
    log(
      key: 'Response Type',
      value: '-> ${options.responseType.toString()}',
      style: defaultRequestStyle,
    );
    log(
      key: 'Follow Redirects',
      value: '-> ${options.followRedirects.toString()}',
      style: defaultRequestStyle,
    );
    // if (_logRequestTimeout) {
    //   logger.info(
    //     'Connection Timeout: ${options.connectTimeout.toString()}',
    //   );
    //   logger.info(
    //     'Send Timeout: ${options.sendTimeout.toString()}',
    //   );
    //   logger.info(
    //     'Receive Timeout: ${options.receiveTimeout.toString()}',
    //   );
    // }
    // logger.info(
    //   'Follow Redirects: ${options.followRedirects.toString()}',
    // );
    // if (_logRequestTimeout) {
    //   logger.info(
    //     'Connection Timeout: ${options.connectTimeout.toString()}',
    //   );
    //   logger.info(
    //     'Send Timeout: ${options.sendTimeout.toString()}',
    //   );
    //   logger.info(
    //     'Receive Timeout: ${options.receiveTimeout.toString()}',
    //   );
    // }
    // logger.info(
    //   'Receive Data When Status Error: ${options.receiveDataWhenStatusError.toString()}',
    // );
    log(
      key: 'Extra',
      value: '-> ${options.extra.toString()}',
      style: defaultRequestStyle,
    );
    // if (_logRequestHeaders) {
    options.headers.removeWhere((key, value) => key == 'enableLogs');
    // _log(
    //   key: 'Headers',
    //   value: '-> ${options.headers.toString()}',
    //   style: _defaultRequestStyle,
    // );
    logHeaders(headers: options.headers, style: defaultRequestStyle);
    // }
    // _log(
    //   key: 'Request Body',
    //   value: '-> ${options.data.toString()}',
    //   style: _defaultRequestStyle,
    // );
    logJson(
      key: 'Request Body:\n',
      value: options.data,
      style: defaultRequestStyle,
    );
  }

  void logError(DioException err) {
    log(key: '[Error] ->', value: '', style: defaultErrorStyle);
    log(
      key: 'DioException: ',
      value: '[${err.type.toString()}]: ${err.message}',
      style: defaultErrorStyle,
    );
  }

  void log({required String key, required String value, Styles? style}) {
    final coloredMessage = Colorize('$key$value').apply(
      style ?? Styles.LIGHT_GRAY,
    );
    logger.info('$coloredMessage');
  }

  void logHeaders({required Map headers, Styles? style}) {
    log(key: 'Headers:', value: '', style: style);
    headers.forEach((key, value) {
      log(
        key: '\t$key: ',
        value: (value is List && value.length == 1)
            ? '[${(value).join(', ')}]'
            : value.toString(),
        style: style,
      );
    });
  }

  BodyType bodyType(dynamic value) {
    if (value.runtimeType == FormData) {
      return BodyType.formData;
    } else if (value.runtimeType == ResponseBody) {
      return BodyType.file;
    } else {
      return BodyType.json;
    }
  }

  void logNewLine() => log(key: '', value: '');
  void logResponse(Response response, {Styles? style, bool error = false}) {
    if (!error) {
      log(key: '[Response] ->', value: '', style: style);
    }
    log(key: 'Uri: ', value: response.realUri.toString(), style: style);
    log(
      key: 'Request Method: ',
      value: response.requestOptions.method,
      style: style,
    );
    log(key: 'Status Code: ', value: '${response.statusCode}', style: style);

    logHeaders(headers: response.headers.map, style: style);

    logJson(
      key: 'Response Body:\n',
      value: response.data,
      style: style,
      isResponse: true,
    );
  }

  void logJson({
    required String key,
    dynamic value,
    Styles? style,
    bool isResponse = false,
  }) {
    String encodedJson = '';
    final type = bodyType(value);
    final isValueNull = value == null;

    switch (type) {
      case BodyType.formData:
        encodedJson = _jsonEncoder.convert(
          Map.fromEntries((value as FormData).fields),
        );
        break;
      case BodyType.file:
        encodedJson = 'File: ${value.runtimeType.toString()}';
        break;
      case BodyType.json:
        encodedJson = _jsonEncoder.convert(isValueNull ? 'null' : value);
        break;
    }

    log(
      key: switch (type) {
        BodyType.formData when !isResponse => '[FormData.fields] $key',
        BodyType.file when !isResponse => '[File] $key',
        BodyType.json when !isValueNull && !isResponse => '[Json] $key',
        _ => key,
      },
      value: encodedJson,
      style: style,
    );

    if (type == BodyType.formData && !isResponse) {
      final files = (value as FormData).files
          .map((e) => e.value.filename ?? 'Null or Empty filename')
          .toList();
      if (files.isNotEmpty) {
        final encodedJson = _jsonEncoder.convert(files);
        log(
          key: '[FormData.files] Request Body:\n',
          value: encodedJson,
          style: style,
        );
      }
    }
  }
}
