import 'package:api_client/api_client.dart';
import 'package:api_client/src/authentication_mangament.dart';
import 'package:api_client/src/token_mangament.dart';
import 'package:api_client/src/utils/auth_interceptor.dart';
import 'package:awesome_dio_interceptor/awesome_dio_interceptor.dart';
import 'package:dio/dio.dart';

class NetworkClient {
  // Private constructor to enforce the singleton pattern
  NetworkClient._();

  // The single, static instance of NetworkClient
  static final NetworkClient _instance = NetworkClient._();

  // The Dio instance, now nullable. It will be null until initialized.
  Dio? _dio;

  // Factory constructor: This is the entry point to get the singleton.
  // It takes the baseUrl as an argument *only the first time* it's called
  // to initialize the client.
  factory NetworkClient({String? baseUrl}) {
    // Check if the _dio client has already been initialized for this instance.
    if (_instance._dio == null) {
      // If not initialized, a baseUrl MUST be provided.
      if (baseUrl == null && Configuration.baseUrl.isEmpty) {
        throw ArgumentError(
          'baseUrl must be provided on the first initialization of NetworkClient.',
        );
      }
      // Call the private initialization method on the singleton instance.
      _instance._initializeClient(
        baseUrl ?? Configuration.baseUrl,
        headers: Configuration.headers,
      );
    } else {
      // If already initialized, and a baseUrl is provided again, you might
      // want to print a warning, throw an error, or simply ignore it.
      // For this example, we'll just ignore it.
      // Example:
      // if (baseUrl != null && _instance._dio?.options.baseUrl != baseUrl) {
      //   print('Warning: NetworkClient already initialized with a different baseUrl.');
      // }
    }
    return _instance; // Always return the same instance
  }

  // Private method to initialize the Dio client.
  // It's prefixed with '_' to make it private to the class.
  void _initializeClient(
    String baseUrl, {
    required Map<String, String> headers,
  }) {
    // var authManager = AuthManager.instance;

    //  var user = await authManager.me();
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10), // 10 seconds
        receiveTimeout: const Duration(seconds: 10), // 10 seconds
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // 'Authorization': ' Bearer $accessToken',
        },
      ),
    );

    // Optional: Add interceptors for logging, authentication, etc.
    // The '!' asserts that _dio is not null here because we just assigned it.
    // _dio!.interceptors.add(
    //   LogInterceptor(requestBody: true, responseBody: true),
    // );

    // adding interceptor for authentication to handle refresh tokens when headers contains www-authenticate: [Bearer error="invalid_token", error_description="The token expired at '08/05/2025 18:20:38'"]

    // _dio!.interceptors.add(
    //   AwesomeDioInterceptor(),
    // );
    _dio?.interceptors.addAll([
      AwesomeDioInterceptor(),
      AuthInterceptor(_dio!, () async {}, (m) {}),
    ]);
  }

  // Getter to provide the initialized Dio client
  Dio get dioClient {
    // Ensure that _initializeClient has been called
    if (_dio == null) {
      throw StateError(
        'NetworkClient has not been initialized. Call NetworkClient(baseUrl: "YOUR_BASE_URL") once to initialize it.',
      );
    }
    // The '!' asserts that _dio is not null because we just checked it.
    return _dio!;
  }
}
