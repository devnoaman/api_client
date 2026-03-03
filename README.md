# api_client

A robust, configurable Flutter package that simplifies HTTP networking by wrapping `dio` with built-in features for authentication, secure storage management, logging, and error tracking.

## Features

- **Global Configuration**: Easily configure base URL, headers, and timeouts for all requests.
- **Controller Pattern**: Use the `BaseController<T>` base class to create organized, maintainable API endpoints with built-in response decoding.
- **Authentication Management**: Built-in support for login, logout, and state management via `AuthManager`.
- **Automatic Token Handling**: Interceptors for automatically appending access tokens and handling token refresh workflows.
- **Secure Storage**: Integrated `flutter_secure_storage` to safely store user data, access tokens, and refresh tokens.
- **Third-Party Integrations**: Easily add Sentry error tracking (`sentry_dio`) and advanced logging (`awesome_dio_interceptor`).

## Getting started

Add `api_client` to your `pubspec.yaml` dependencies.

```yaml
dependencies:
  api_client: ^0.0.1
```

Initialize the global configuration before making any requests, typically in your `main()` method:

```dart
import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

void main() {
  // Set your API Base URL
  Configuration.baseUrl = 'https://api.example.com/v1';
  
  // Optional flag to enable advanced logging
  Configuration.enableLogs = true;

  runApp(const MainApp());
}
```

## Usage

### 1. Defining an API Controller

Create clear and type-safe endpoints by extending `BaseController<T>`:

```dart
import 'package:api_client/api_client.dart';

base class GetUsersController extends BaseController<List<User>> {
  GetUsersController()
      : super(
          path: '/users',
          method: HTTPMethod.get,
          authenticated: true, // Automatically includes auth headers
          responseDecoder: (data) =>
              (data as List).map((e) => User.fromJson(e)).toList(),
        );
}
```
### Using the controller

```dart
final controller = GetUsersController();
```

### Calling the controller with status result

```dart
final result = await controller.callWithResult();
switch (result) {
  case Success(data: final data):
    // Handle success
    break;
  case Failed(error: final error, stackTrace: final stackTrace, data: final data):
    // Handle error
    break;
}
```

### Calling the controller without status result

```dart
final result = await controller.call();
if(result.isEmpty){
  // handle empty result
}else{
  // handle result
}
```

### 2. Authentication Flow

Use `AuthManager` to handle login, which automatically extracts and stores the tokens securely.

```dart
final authManager = AuthManager.instance;

// Login and save tokens
final user = await authManager.login(
  path: '/auth/login',
  data: {
    'email': 'user@example.com',
    'password': 'securepassword',
  },
  decoder: (data) => UserModel.fromJson(data),
);

// Get current user from secure storage
final cachedUser = await authManager.me();

// Logout and clear tokens
await authManager.logout(
  path: '/auth/logout',
  decoder: (data) => data,
);
```

### 3. Listening to Authentication Events

You can listen to `authManagerStream` to respond to session events (like session expiry) across your app:

```dart
AuthManager.instance.authManagerStream.listen((event) {
  if (event.type == AuthManagerEventType.sessionExpired) {
    // Navigate to Login Screen
  }
});
```

## Additional information

For more examples, please refer to the `/example` folder in the package repository. 
To contribute or report issues, please check the repository's issue tracker.
