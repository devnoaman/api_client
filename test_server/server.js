/**
 * api_client Test Server
 *
 * Endpoints:
 *   POST /auth/login          - Returns access + refresh tokens
 *   POST /auth/refresh        - Refreshes the access token
 *   POST /auth/logout         - Clears the session
 *   GET  /public/ping         - Unprotected endpoint
 *   GET  /users               - Protected (requires Bearer token)
 *   GET  /users/:id           - Protected, returns a single user
 *   POST /users               - Protected, creates a user (returns 201)
 *
 * Tokens are simple signed strings — no JWT library needed.
 * Access token expires in 30 seconds (configurable via ACCESS_TTL_MS).
 * Refresh token expires in 5 minutes.
 */

const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 3000;
const ACCESS_TTL_MS = parseInt(process.env.ACCESS_TTL_MS ?? '30000');  // 30s
const REFRESH_TTL_MS = 5 * 60 * 1000; // 5m

// ─── In-memory store ────────────────────────────────────────────────────────
const USERS = [
  { id: '1', name: 'Alice',   email: 'alice@example.com', role: 'admin' },
  { id: '2', name: 'Bob',     email: 'bob@example.com',   role: 'user'  },
  { id: '3', name: 'Charlie', email: 'charlie@example.com', role: 'user' },
];

const CREDENTIALS = {
  'alice@example.com': 'password123',
  'bob@example.com':   'password456',
};

// token -> { userId, expiresAt }
const accessStore  = new Map();
const refreshStore = new Map();

// ─── Token helpers ────────────────────────────────────────────────────────────
function makeToken() {
  return crypto.randomBytes(24).toString('hex');
}

function issueTokens(userId) {
  const access  = makeToken();
  const refresh = makeToken();
  accessStore.set(access,   { userId, expiresAt: Date.now() + ACCESS_TTL_MS });
  refreshStore.set(refresh, { userId, expiresAt: Date.now() + REFRESH_TTL_MS });
  return { access, refresh };
}

function validateAccess(token) {
  const record = accessStore.get(token);
  if (!record) return null;
  if (Date.now() > record.expiresAt) {
    accessStore.delete(token);
    return null; // expired
  }
  return record;
}

function validateRefresh(token) {
  const record = refreshStore.get(token);
  if (!record) return null;
  if (Date.now() > record.expiresAt) {
    refreshStore.delete(token);
    return null;
  }
  return record;
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────
function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', chunk => (raw += chunk));
    req.on('end', () => {
      try { resolve(raw ? JSON.parse(raw) : {}); }
      catch { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

function send(res, statusCode, body) {
  const json = JSON.stringify(body);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(json),
  });
  res.end(json);
}

function extractBearer(req) {
  const auth = req.headers['authorization'] ?? '';
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function requireAuth(req, res) {
  const token = extractBearer(req);
  if (!token) {
    send(res, 401, { error: 'Missing Authorization header' });
    return null;
  }
  const record = validateAccess(token);
  if (!record) {
    send(res, 401, {
      error: 'Access token expired or invalid',
      hint:  'Use POST /auth/refresh to get a new token',
    });
    return null;
  }
  return record;
}

// ─── Route handlers ───────────────────────────────────────────────────────────
async function handleLogin(req, res) {
  const body = await readBody(req);
  const { email, password } = body;

  log(`Login attempt: ${email}`);

  if (!email || !password) {
    return send(res, 400, { error: 'email and password are required' });
  }
  if (CREDENTIALS[email] !== password) {
    return send(res, 401, { error: 'Invalid credentials' });
  }

  const user = USERS.find(u => u.email === email);
  const tokens = issueTokens(user.id);

  log(`Issued tokens for ${email} — access expires in ${ACCESS_TTL_MS / 1000}s`);
  send(res, 200, {
    user,
    accessToken:  tokens.access,
    refreshToken: tokens.refresh,
  });
}

async function handleRefresh(req, res) {
  const body = await readBody(req);
  const refreshToken = body.refreshToken;

  log(`Refresh attempt with token: ${refreshToken?.slice(0, 8)}...`);

  if (!refreshToken) {
    return send(res, 400, { error: 'refreshToken is required' });
  }

  const record = validateRefresh(refreshToken);
  if (!record) {
    return send(res, 401, { error: 'Refresh token expired or invalid. Please login again.' });
  }

  // Rotate tokens
  refreshStore.delete(refreshToken);
  const tokens = issueTokens(record.userId);

  log(`Rotated tokens for userId=${record.userId}`);
  send(res, 200, {
    accessToken:  tokens.access,
    refreshToken: tokens.refresh,
  });
}

async function handleLogout(req, res) {
  const token = extractBearer(req);
  if (token) {
    accessStore.delete(token);
    log(`Logged out token: ${token.slice(0, 8)}...`);
  }
  send(res, 200, { message: 'Logged out successfully' });
}

function handlePing(req, res) {
  send(res, 200, { message: 'pong', timestamp: new Date().toISOString() });
}

function handleListUsers(req, res) {
  const record = requireAuth(req, res);
  if (!record) return;
  send(res, 200, USERS);
}

function handleGetUser(req, res, id) {
  const record = requireAuth(req, res);
  if (!record) return;
  const user = USERS.find(u => u.id === id);
  if (!user) return send(res, 404, { error: `User ${id} not found` });
  send(res, 200, user);
}

async function handleCreateUser(req, res) {
  const record = requireAuth(req, res);
  if (!record) return;
  const body = await readBody(req);
  const { name, email, role = 'user' } = body;
  if (!name || !email) {
    return send(res, 400, { error: 'name and email are required' });
  }
  const newUser = { id: String(USERS.length + 1), name, email, role };
  USERS.push(newUser);
  log(`Created user: ${JSON.stringify(newUser)}`);
  send(res, 201, newUser);
}

// ─── Router ───────────────────────────────────────────────────────────────────
async function router(req, res) {
  const url    = new URL(req.url, `http://localhost:${PORT}`);
  const path   = url.pathname;
  const method = req.method.toUpperCase();

  log(`${method} ${path}`);

  // CORS (handy if testing from a browser)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  if (method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  try {
    if (method === 'POST' && path === '/auth/login')   return await handleLogin(req, res);
    if (method === 'POST' && path === '/auth/refresh') return await handleRefresh(req, res);
    if (method === 'POST' && path === '/auth/logout')  return await handleLogout(req, res);
    if (method === 'GET'  && path === '/public/ping')  return handlePing(req, res);
    if (method === 'GET'  && path === '/users')        return handleListUsers(req, res);
    if (method === 'POST' && path === '/users')        return await handleCreateUser(req, res);

    // GET /users/:id
    const userMatch = path.match(/^\/users\/([^/]+)$/);
    if (method === 'GET' && userMatch) return handleGetUser(req, res, userMatch[1]);

    send(res, 404, { error: `No handler for ${method} ${path}` });
  } catch (err) {
    console.error('Unhandled error:', err);
    send(res, 500, { error: 'Internal server error', detail: err.message });
  }
}

// ─── Startup ──────────────────────────────────────────────────────────────────
function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

http.createServer(router).listen(PORT, () => {
  log(`Test server running at http://localhost:${PORT}`);
  log(`Access token TTL: ${ACCESS_TTL_MS / 1000}s  |  Refresh TTL: ${REFRESH_TTL_MS / 60000}m`);
  log('');
  log('Endpoints:');
  log('  POST /auth/login          {"email":"alice@example.com","password":"password123"}');
  log('  POST /auth/refresh        {"refreshToken":"<token>"}');
  log('  POST /auth/logout         (Bearer token in header)');
  log('  GET  /public/ping         (no auth)');
  log('  GET  /users               (Bearer token required)');
  log('  GET  /users/:id           (Bearer token required)');
  log('  POST /users               {"name":"...","email":"..."}');
});
