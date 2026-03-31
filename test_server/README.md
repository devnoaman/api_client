# Test Server

A zero-dependency Node.js server for testing the `api_client` package locally.  
No `npm install` required — uses only Node.js built-ins.

## Start

```bash
node test_server/server.js
```

Or with a shorter access token TTL (useful for testing token refresh):

```bash
ACCESS_TTL_MS=10000 node test_server/server.js   # token expires in 10s
```

---

## Endpoints

| Method | Path             | Auth? | Description                        |
|--------|------------------|-------|------------------------------------|
| POST   | `/auth/login`    | ✗     | Login, returns access+refresh token |
| POST   | `/auth/refresh`  | ✗     | Rotate tokens                      |
| POST   | `/auth/logout`   | ✓     | Invalidate access token            |
| GET    | `/public/ping`   | ✗     | Health check                       |
| GET    | `/users`         | ✓     | List all users                     |
| GET    | `/users/:id`     | ✓     | Get a user by ID                   |
| POST   | `/users`         | ✓     | Create a user (returns 201)        |

---

## Quick Test with `curl`

### 1. Login
```bash
curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","password":"password123"}' | jq
```

### 2. List users (paste your token)
```bash
curl -s http://localhost:3000/users \
  -H "Authorization: Bearer <access_token>" | jq
```

### 3. Create a user (returns 201 — good for testing `successStatusCodes: [200, 201]`)
```bash
curl -s -X POST http://localhost:3000/users \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Dave","email":"dave@example.com"}' | jq
```

### 4. Refresh token
```bash
curl -s -X POST http://localhost:3000/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"<refresh_token>"}' | jq
```

### 5. Public ping (no auth)
```bash
curl -s http://localhost:3000/public/ping | jq
```

---

## Flutter / api_client Configuration

```dart
void main() {
  Configuration.baseUrl    = 'http://localhost:3000';
  Configuration.refreshUrl = '/auth/refresh';
  Configuration.tokenKeyName = 'accessToken';
  Configuration.enableLogs = true;

  runApp(const MainApp());
}
```

### Example — protected endpoint
```dart
base class GetUsersController extends BaseController<List<Map>> {
  GetUsersController() : super(
    path: '/users',
    method: HTTPMethod.get,
    authenticated: true,
    responseDecoder: (data) => List<Map>.from(data),
  );
}
```

### Example — create user (status 201)
```dart
base class CreateUserController extends BaseController<Map> {
  CreateUserController(Map<String, dynamic> body) : super(
    path: '/users',
    method: HTTPMethod.post,
    data: body,
    authenticated: true,
    successStatusCodes: const [200, 201],
    responseDecoder: (data) => Map.from(data),
  );
}
```

### Example — public endpoint
```dart
base class PingController extends BaseController<Map> {
  PingController() : super(
    path: '/public/ping',
    method: HTTPMethod.get,
    authenticated: false,
    responseDecoder: (data) => Map.from(data),
  );
}
```
