// Serveur Strasse (Cloudflare Worker + D1). Comptes à connaissance nulle et synchronisation chiffrée de bout en bout.
// Le serveur ne voit jamais : l'e-mail, le mot de passe, la clé de chiffrement, ni le contenu des favoris/trajets.

const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const SESSION_MS = 60 * 24 * 3600 * 1000;
const REPORT_TTL_MS = { accident: 3 * 3600e3, roadwork: 24 * 3600e3, slowdown: 1 * 3600e3, closure: 6 * 3600e3, obstacle: 2 * 3600e3, danger: 2 * 3600e3, other: 2 * 3600e3 };
const MAX_BLOB = 64 * 1024; // 64 Ko par élément
const MAX_ITEMS_PUSH = 500;

const enc = new TextEncoder();
const reply = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
const fail = (status, message, code) => reply({ error: { message, code: code || String(status) } }, status);

async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', typeof s === 'string' ? enc.encode(s) : s);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function randomHex(n) {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
const isHex64 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
const isB64 = (s, max = 4096) => typeof s === 'string' && s.length > 0 && s.length <= max && /^[A-Za-z0-9_\-+/=]+$/.test(s);

async function limit(env, key, max, windowMs) {
  const now = Date.now();
  const row = await env.DB.prepare('SELECT n, window_start FROM rate WHERE k = ?').bind(key).first();
  if (!row || now - row.window_start > windowMs) {
    await env.DB.prepare('INSERT OR REPLACE INTO rate (k, n, window_start) VALUES (?, 1, ?)').bind(key, now).run();
    return true;
  }
  if (row.n >= max) return false;
  await env.DB.prepare('UPDATE rate SET n = n + 1 WHERE k = ?').bind(key).run();
  return true;
}

async function body(request) {
  try {
    const t = await request.text();
    if (t.length > 700 * 1024) return null;
    return JSON.parse(t);
  } catch {
    return null;
  }
}

async function newSession(env, emailId) {
  const token = randomHex(32);
  await env.DB.prepare('INSERT INTO sessions (token_hash, email_id, expires_at) VALUES (?, ?, ?)').bind(await sha256Hex(token), emailId, Date.now() + SESSION_MS).run();
  return token;
}

async function authed(request, env) {
  const h = request.headers.get('authorization') || '';
  if (!h.startsWith('Bearer ')) return null;
  const row = await env.DB.prepare('SELECT email_id, expires_at FROM sessions WHERE token_hash = ?').bind(await sha256Hex(h.slice(7))).first();
  if (!row || row.expires_at < Date.now()) return null;
  return row.email_id;
}

async function hashSecret(salt, secret) {
  return sha256Hex(`${salt}|${secret}`);
}

const routes = {
  // ------------------------------------------------------------ Comptes
  async register(request, env) {
    const b = await body(request);
    if (!b || !isHex64(b.emailId) || !isB64(b.authKey, 128) || !isB64(b.wrappedMk) || !isB64(b.wrappedMkRec) || !isB64(b.recoveryVerifier, 128)) return fail(400, 'Requête invalide.', 'bad_request');
    const ip = request.headers.get('cf-connecting-ip') || 'x';
    if (!(await limit(env, `reg:${await sha256Hex(ip)}`, 10, 3600e3))) return fail(429, 'Trop de créations de compte. Réessayez plus tard.', 'rate_limited');
    const exists = await env.DB.prepare('SELECT 1 FROM accounts WHERE email_id = ?').bind(b.emailId).first();
    if (exists) return fail(409, 'Un compte existe déjà avec cet e-mail.', 'exists');
    const salt = randomHex(16), rsalt = randomHex(16);
    await env.DB.prepare('INSERT INTO accounts (email_id, auth_salt, auth_hash, wrapped_mk, wrapped_mk_rec, recovery_salt, recovery_hash, created_at) VALUES (?,?,?,?,?,?,?,?)')
      .bind(b.emailId, salt, await hashSecret(salt, b.authKey), b.wrappedMk, b.wrappedMkRec, rsalt, await hashSecret(rsalt, b.recoveryVerifier), Date.now()).run();
    return reply({ token: await newSession(env, b.emailId) }, 201);
  },

  async login(request, env) {
    const b = await body(request);
    if (!b || !isHex64(b.emailId) || !isB64(b.authKey, 128)) return fail(400, 'Requête invalide.', 'bad_request');
    if (!(await limit(env, `login:${b.emailId}`, 10, 15 * 60e3))) return fail(429, 'Trop de tentatives. Réessayez dans quelques minutes.', 'rate_limited');
    const a = await env.DB.prepare('SELECT * FROM accounts WHERE email_id = ?').bind(b.emailId).first();
    // Même réponse que le compte existe ou non : on ne révèle pas quels e-mails sont inscrits.
    const ok = a && safeEqual(await hashSecret(a.auth_salt, b.authKey), a.auth_hash);
    if (!ok) return fail(401, 'E-mail ou mot de passe incorrect.', 'unauthorized');
    return reply({ token: await newSession(env, b.emailId), wrappedMk: a.wrapped_mk });
  },

  async recoverStart(request, env) {
    const b = await body(request);
    if (!b || !isHex64(b.emailId) || !isB64(b.recoveryVerifier, 128)) return fail(400, 'Requête invalide.', 'bad_request');
    if (!(await limit(env, `rec:${b.emailId}`, 5, 3600e3))) return fail(429, 'Trop de tentatives. Réessayez plus tard.', 'rate_limited');
    const a = await env.DB.prepare('SELECT * FROM accounts WHERE email_id = ?').bind(b.emailId).first();
    if (!a || !safeEqual(await hashSecret(a.recovery_salt, b.recoveryVerifier), a.recovery_hash)) return fail(401, 'E-mail ou clé de récupération incorrects.', 'unauthorized');
    return reply({ wrappedMkRec: a.wrapped_mk_rec });
  },

  async recoverFinish(request, env) {
    const b = await body(request);
    if (!b || !isHex64(b.emailId) || !isB64(b.recoveryVerifier, 128) || !isB64(b.newAuthKey, 128) || !isB64(b.wrappedMk)) return fail(400, 'Requête invalide.', 'bad_request');
    const a = await env.DB.prepare('SELECT * FROM accounts WHERE email_id = ?').bind(b.emailId).first();
    if (!a || !safeEqual(await hashSecret(a.recovery_salt, b.recoveryVerifier), a.recovery_hash)) return fail(401, 'E-mail ou clé de récupération incorrects.', 'unauthorized');
    const salt = randomHex(16);
    await env.DB.prepare('UPDATE accounts SET auth_salt = ?, auth_hash = ?, wrapped_mk = ? WHERE email_id = ?').bind(salt, await hashSecret(salt, b.newAuthKey), b.wrappedMk, b.emailId).run();
    await env.DB.prepare('DELETE FROM sessions WHERE email_id = ?').bind(b.emailId).run();
    return reply({ token: await newSession(env, b.emailId) });
  },

  async logout(request, env) {
    const h = request.headers.get('authorization') || '';
    if (h.startsWith('Bearer ')) await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256Hex(h.slice(7))).run();
    return reply({ ok: true });
  },

  async deleteAccount(request, env) {
    const id = await authed(request, env);
    if (!id) return fail(401, 'Session expirée.', 'unauthorized');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM items WHERE email_id = ?').bind(id),
      env.DB.prepare('DELETE FROM sessions WHERE email_id = ?').bind(id),
      env.DB.prepare('DELETE FROM accounts WHERE email_id = ?').bind(id),
    ]);
    return reply({ ok: true });
  },

  // ------------------------------------------------------ Synchronisation chiffrée
  async pull(request, env, url) {
    const id = await authed(request, env);
    if (!id) return fail(401, 'Session expirée.', 'unauthorized');
    const since = Number(url.searchParams.get('since') || 0) || 0;
    const rows = await env.DB.prepare('SELECT kind, id, updated_at, deleted, blob FROM items WHERE email_id = ? AND updated_at > ? ORDER BY updated_at LIMIT 2000').bind(id, since).all();
    return reply({
      serverTime: Date.now(),
      items: rows.results.map((r) => ({ kind: r.kind, id: r.id, updatedAt: r.updated_at, deleted: !!r.deleted, blob: r.blob })),
    });
  },

  async push(request, env) {
    const id = await authed(request, env);
    if (!id) return fail(401, 'Session expirée.', 'unauthorized');
    const b = await body(request);
    if (!b || !Array.isArray(b.items) || b.items.length > MAX_ITEMS_PUSH) return fail(400, 'Requête invalide.', 'bad_request');
    const stmts = [];
    const now = Date.now();
    for (const it of b.items) {
      if (!it || !/^[a-z]{1,12}$/.test(it.kind) || typeof it.id !== 'string' || it.id.length > 80) return fail(400, 'Élément invalide.', 'bad_request');
      if (!it.deleted && (typeof it.blob !== 'string' || it.blob.length > MAX_BLOB)) return fail(413, 'Élément trop volumineux.', 'too_large');
      // La plus récente modification gagne ; l'horodatage de réception sert de curseur de synchronisation.
      stmts.push(env.DB.prepare(
        'INSERT INTO items (email_id, kind, id, updated_at, deleted, blob) VALUES (?,?,?,?,?,?) ON CONFLICT(email_id, kind, id) DO UPDATE SET updated_at = excluded.updated_at, deleted = excluded.deleted, blob = excluded.blob WHERE excluded.updated_at >= items.updated_at',
      ).bind(id, it.kind, it.id, now, it.deleted ? 1 : 0, it.deleted ? null : it.blob));
    }
    if (stmts.length) await env.DB.batch(stmts);
    return reply({ serverTime: now });
  },

  // ------------------------------------------------------------ Signalements (publics)
  async reportsList(request, env, url) {
    const p = (url.searchParams.get('bbox') || '').split(',').map(Number);
    if (p.length !== 4 || p.some((x) => !Number.isFinite(x))) return fail(400, 'bbox invalide.', 'bad_request');
    const [w, s, e, n] = p;
    if (Math.abs(e - w) > 2 || Math.abs(n - s) > 2) return fail(400, 'Zone trop grande.', 'bad_request');
    const rows = await env.DB.prepare('SELECT * FROM reports WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND expires_at > ? AND rejects < confirms + 2 LIMIT 200').bind(s, n, w, e, Date.now()).all();
    return reply({ reports: rows.results.map(reportJson) });
  },

  async reportCreate(request, env) {
    const id = await authed(request, env);
    if (!id) return fail(401, 'Connectez-vous pour signaler un événement.', 'unauthorized');
    const b = await body(request);
    if (!b || !(b.type in REPORT_TTL_MS) || !Number.isFinite(b.lat) || !Number.isFinite(b.lon) || Math.abs(b.lat) > 90 || Math.abs(b.lon) > 180) return fail(400, 'Requête invalide.', 'bad_request');
    if (!(await limit(env, `rep:${id}`, 20, 3600e3))) return fail(429, 'Trop de signalements. Réessayez plus tard.', 'rate_limited');
    const lat = Math.round(b.lat * 1e4) / 1e4, lon = Math.round(b.lon * 1e4) / 1e4; // ~11 m
    const now = Date.now();
    const near = await env.DB.prepare('SELECT * FROM reports WHERE type = ? AND expires_at > ? AND ABS(lat - ?) < 0.0004 AND ABS(lon - ?) < 0.0006 LIMIT 1').bind(b.type, now, lat, lon).first();
    if (near) {
      await env.DB.prepare('UPDATE reports SET confirms = confirms + 1, expires_at = ? WHERE id = ?').bind(now + REPORT_TTL_MS[b.type], near.id).run();
      return reply(reportJson({ ...near, confirms: near.confirms + 1, expires_at: now + REPORT_TTL_MS[b.type] }), 200);
    }
    const rid = randomHex(12);
    const row = { id: rid, type: b.type, lat, lon, created_at: now, expires_at: now + REPORT_TTL_MS[b.type], confirms: 1, rejects: 0 };
    await env.DB.prepare('INSERT INTO reports (id, type, lat, lon, created_at, expires_at, confirms, rejects) VALUES (?,?,?,?,?,?,?,?)').bind(rid, b.type, lat, lon, row.created_at, row.expires_at, 1, 0).run();
    return reply(reportJson(row), 201);
  },

  async feedback(request, env) {
    const input = await body(request);
    if (!input || typeof input.message !== 'string') return fail(400, 'Message invalide.', 'bad_request');
    const message = input.message.trim();
    if (message.length < 10 || message.length > 4000) return fail(400, 'Le message doit contenir entre 10 et 4 000 caractères.', 'bad_request');

    const replyTo = typeof input.replyTo === 'string' ? input.replyTo.trim() : '';
    if (replyTo && (replyTo.length > 254 || /[\r\n]/.test(replyTo) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(replyTo))) {
      return fail(400, 'Adresse de réponse invalide.', 'bad_reply_to');
    }

    const ip = request.headers.get('cf-connecting-ip') || 'x';
    if (!(await limit(env, 'feedback:' + await sha256Hex(ip), 5, 3600e3))) {
      return fail(429, 'Trop de retours envoyés. Réessayez plus tard.', 'rate_limited');
    }

    if (!env.RESEND_API_KEY || !env.FEEDBACK_TO || !env.FEEDBACK_FROM) {
      return fail(503, 'Le service de retours n’est pas encore configuré sur le serveur Strasse.', 'feedback_not_configured');
    }

    const now = new Date();
    const two = (value) => String(value).padStart(2, '0');
    const subject = 'Feedback ' + two(now.getUTCDate()) + '/' + two(now.getUTCMonth() + 1) + '/' + now.getUTCFullYear();
    const email = {
      from: env.FEEDBACK_FROM,
      to: [env.FEEDBACK_TO],
      subject,
      text: message,
      ...(replyTo ? { reply_to: replyTo } : {}),
    };

    let response;
    let result;
    try {
      response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + env.RESEND_API_KEY,
          'Content-Type': 'application/json',
          'User-Agent': 'Strasse-Worker/1.0',
        },
        body: JSON.stringify(email),
      });
      result = await response.json();
    } catch (_) {
      return fail(502, 'Le fournisseur e-mail est injoignable. Réessayez plus tard.', 'feedback_delivery_failed');
    }

    if (!response.ok || !result || typeof result.id !== 'string' || !result.id) {
      return fail(502, 'Le fournisseur e-mail n’a pas accepté le message.', 'feedback_delivery_failed');
    }
    return reply({ success: true });
  },

  async reportVote(request, env, url, rid, up) {
    const id = await authed(request, env);
    if (!id) return fail(401, 'Connectez-vous pour voter.', 'unauthorized');
    const r = await env.DB.prepare('SELECT * FROM reports WHERE id = ? AND expires_at > ?').bind(rid, Date.now()).first();
    if (!r) return fail(404, 'Signalement introuvable ou expiré.', 'not_found');
    // Un seul vote par compte (condensé, sans lien lisible avec le compte).
    const voter = await sha256Hex(`${id}|${rid}`);
    const dup = await env.DB.prepare('SELECT 1 FROM report_votes WHERE report_id = ? AND voter = ?').bind(rid, voter).first();
    if (dup) return reply(reportJson(r));
    await env.DB.prepare('INSERT INTO report_votes (report_id, voter) VALUES (?, ?)').bind(rid, voter).run();
    const col = up ? 'confirms' : 'rejects';
    await env.DB.prepare(`UPDATE reports SET ${col} = ${col} + 1 WHERE id = ?`).bind(rid).run();
    const next = await env.DB.prepare('SELECT * FROM reports WHERE id = ?').bind(rid).first();
    return reply(reportJson(next));
  },
};

function reportJson(r) {
  return { id: r.id, type: r.type, lat: r.lat, lon: r.lon, createdAt: new Date(r.created_at).toISOString(), expiresAt: new Date(r.expires_at).toISOString(), status: r.rejects > r.confirms ? 'doubtful' : 'active', confirmations: r.confirms, rejections: r.rejects };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = request.method;
    try {
      if (m === 'OPTIONS') return new Response(null, { status: 204 });
      if (url.pathname === '/v1/health') return reply({ ok: true });
      if (m === 'POST' && url.pathname === '/v1/feedback') return await routes.feedback(request, env);
      if (m === 'POST' && url.pathname === '/v1/auth/register') return await routes.register(request, env);
      if (m === 'POST' && url.pathname === '/v1/auth/login') return await routes.login(request, env);
      if (m === 'POST' && url.pathname === '/v1/auth/recover/start') return await routes.recoverStart(request, env);
      if (m === 'POST' && url.pathname === '/v1/auth/recover/finish') return await routes.recoverFinish(request, env);
      if (m === 'POST' && url.pathname === '/v1/auth/logout') return await routes.logout(request, env);
      if (m === 'DELETE' && url.pathname === '/v1/account') return await routes.deleteAccount(request, env);
      if (m === 'GET' && url.pathname === '/v1/sync/pull') return await routes.pull(request, env, url);
      if (m === 'POST' && url.pathname === '/v1/sync/push') return await routes.push(request, env);
      if (m === 'GET' && url.pathname === '/v1/reports') return await routes.reportsList(request, env, url);
      if (m === 'POST' && url.pathname === '/v1/reports') return await routes.reportCreate(request, env);
      const v = url.pathname.match(/^\/v1\/reports\/([0-9a-f]{24})\/(confirm|reject)$/);
      if (m === 'POST' && v) return await routes.reportVote(request, env, url, v[1], v[2] === 'confirm');
      return fail(404, 'Route inconnue.', 'not_found');
    } catch (e) {
      return fail(500, 'Erreur du serveur.', 'server_error');
    }
  },
};
