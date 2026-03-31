import 'package:api_client/api_client.dart';
import 'package:example/features/users/models/user_model.dart';

/// GET /users  — protected, requires Bearer token.
base class GetUsersController extends BaseController<List<UserModel>> {
  GetUsersController()
      : super(
          path: '/users',
          method: HTTPMethod.get,
          authenticated: true,
          responseDecoder: (data) =>
              (data as List).map((e) => UserModel.fromJson(Map<String, dynamic>.from(e))).toList(),
        );
}

/// GET /users/:id  — protected.
base class GetUserController extends BaseController<UserModel> {
  GetUserController(String id)
      : super(
          path: '/users/$id',
          method: HTTPMethod.get,
          authenticated: true,
          responseDecoder: (data) =>
              UserModel.fromJson(Map<String, dynamic>.from(data)),
        );
}

/// POST /users  — protected, returns 201 Created.
base class CreateUserController extends BaseController<UserModel> {
  CreateUserController({required String name, required String email})
      : super(
          path: '/users',
          method: HTTPMethod.post,
          authenticated: true,
          data: {'name': name, 'email': email},
          successStatusCodes: const [200, 201],
          responseDecoder: (data) =>
              UserModel.fromJson(Map<String, dynamic>.from(data)),
        );
}

/// GET /public/ping  — no auth needed.
base class PingController extends BaseController<Map<String, dynamic>> {
  PingController()
      : super(
          path: '/public/ping',
          method: HTTPMethod.get,
          authenticated: false,
          responseDecoder: (data) => Map<String, dynamic>.from(data),
        );
}
