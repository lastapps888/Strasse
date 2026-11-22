import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker from '../src/worker.js';

// Mini D1 au-dessus de node:sqlite (mêmes méthodes que D1 : prepare/bind/first/all/run/batch).
function makeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    first: async () => db.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => { db.prepare(sql).run(...args); return {}; },
    _run: () => db.prepare(sql).run(...args),
  });
  return { prepare: (s) => stmt(s), batch: async (list) => { for (const s of list) s._run(); return []; } };
}

const env = { DB: makeD1() };
const call = async (method, path, body, token) => {
  const r = await worker.fetch(new Request('https://x.test' + path, { method, body: body ? JSON.stringify(body) : undefined, headers: token ? { authorization: 'Bearer ' + token } : {} }), env);
  return { status: r.status, json: await r.json() };
};
const hex = (c) => c.repeat(64);

test('inscription, connexion, synchronisation chiffrée, suppression', async () => {
  const reg = { emailId: hex('a'), authKey: 'QVVUSEtFWQ', wrappedMk: 'V1JBUFBFRA', wrappedMkRec: 'V1JBUFBFRDI', recoveryVerifier: 'UkVD' };
  let r = await call('POST', '/v1/auth/register', reg);
  assert.equal(r.status, 201);
  const token = r.json.token;
  assert.equal((await call('POST', '/v1/auth/register', reg)).status, 409);
  r = await call('POST', '/v1/auth/login', { emailId: hex('a'), authKey: 'mauvais' });
  assert.equal(r.status, 401);
  r = await call('POST', '/v1/auth/login', { emailId: hex('a'), authKey: 'QVVUSEtFWQ' });
  assert.equal(r.status, 200);
  assert.equal(r.json.wrappedMk, 'V1JBUFBFRA');

  assert.equal((await call('GET', '/v1/sync/pull')).status, 401);
  r = await call('POST', '/v1/sync/push', { items: [{ kind: 'fav', id: 'f1', blob: 'Q0lQSEVS' }, { kind: 'fav', id: 'f2', blob: 'Q0lQSEVS' }] }, token);
  assert.equal(r.status, 200);
  r = await call('GET', '/v1/sync/pull?since=0', null, token);
  assert.equal(r.json.items.length, 2);
  const cursor = r.json.serverTime;
  await new Promise((s) => setTimeout(s, 5));
  await call('POST', '/v1/sync/push', { items: [{ kind: 'fav', id: 'f1', deleted: true }] }, token);
  r = await call('GET', '/v1/sync/pull?since=' + cursor, null, token);
  assert.equal(r.json.items.length, 1);
  assert.equal(r.json.items[0].deleted, true);
  assert.equal(r.json.items[0].blob, null);

  r = await call('POST', '/v1/sync/push', { items: [{ kind: 'fav', id: 'big', blob: 'A'.repeat(70000) }] }, token);
  assert.equal(r.status, 413);

  // Récupération avec la clé de récupération.
  assert.equal((await call('POST', '/v1/auth/recover/start', { emailId: hex('a'), recoveryVerifier: 'faux' })).status, 401);
  r = await call('POST', '/v1/auth/recover/start', { emailId: hex('a'), recoveryVerifier: 'UkVD' });
  assert.equal(r.json.wrappedMkRec, 'V1JBUFBFRDI');
  r = await call('POST', '/v1/auth/recover/finish', { emailId: hex('a'), recoveryVerifier: 'UkVD', newAuthKey: 'TkVX', wrappedMk: 'TkVXV1JBUA' });
  assert.equal(r.status, 200);
  assert.equal((await call('GET', '/v1/sync/pull', null, token)).status, 401, 'anciennes sessions révoquées');
  assert.equal((await call('POST', '/v1/auth/login', { emailId: hex('a'), authKey: 'QVVUSEtFWQ' })).status, 401);
  r = await call('POST', '/v1/auth/login', { emailId: hex('a'), authKey: 'TkVX' });
  assert.equal(r.json.wrappedMk, 'TkVXV1JBUA');

  assert.equal((await call('DELETE', '/v1/account', null, r.json.token)).status, 200);
  assert.equal((await call('POST', '/v1/auth/login', { emailId: hex('a'), authKey: 'TkVX' })).status, 401);
});

test('signalements : création, fusion, vote unique, expiration par zone', async () => {
  const reg = { emailId: hex('b'), authKey: 'QQ', wrappedMk: 'Vw', wrappedMkRec: 'Vw', recoveryVerifier: 'Ug' };
  const token = (await call('POST', '/v1/auth/register', reg)).json.token;
  assert.equal((await call('POST', '/v1/reports', { type: 'accident', lat: 48.5, lon: 7.7 })).status, 401);
  let r = await call('POST', '/v1/reports', { type: 'accident', lat: 48.5, lon: 7.7 }, token);
  assert.equal(r.status, 201);
  const id = r.json.id;
  r = await call('POST', '/v1/reports', { type: 'accident', lat: 48.50001, lon: 7.70001 }, token);
  assert.equal(r.status, 200);
  assert.equal(r.json.id, id);
  r = await call('GET', '/v1/reports?bbox=7.6,48.4,7.8,48.6');
  assert.equal(r.json.reports.length, 1);
  assert.equal((await call('GET', '/v1/reports?bbox=0,0,50,50')).status, 400);
  await call('POST', `/v1/reports/${id}/confirm`, null, token);
  r = await call('POST', `/v1/reports/${id}/confirm`, null, token);
  assert.equal(r.json.confirmations, 3, 'vote en double ignoré');
  assert.equal((await call('POST', '/v1/reports', { type: 'inconnu', lat: 1, lon: 1 }, token)).status, 400);
});


test('feedback refuse de confirmer lorsque le fournisseur n’est pas configuré', async () => {
  const request = new Request('https://x.test/v1/feedback', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '203.0.113.10' },
    body: JSON.stringify({ message: 'Message de retour suffisamment long.' }),
  });
  const response = await worker.fetch(request, env);
  const json = await response.json();
  assert.equal(response.status, 503);
  assert.equal(json.success, undefined);
  assert.equal(json.error.code, 'feedback_not_configured');
});

test('feedback transmet au fournisseur avec les secrets serveur et confirme son acceptation', async () => {
  const originalFetch = globalThis.fetch;
  let requestUrl;
  let requestOptions;
  globalThis.fetch = async (url, options) => {
    requestUrl = String(url);
    requestOptions = options;
    return new Response(JSON.stringify({ id: 'email_test_123' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };

  try {
    const payload = {
      message: 'Retour de test suffisamment long.',
      replyTo: 'person@example.test',
    };
    const response = await worker.fetch(new Request('https://x.test/v1/feedback', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '203.0.113.11' },
      body: JSON.stringify(payload),
    }), {
      ...env,
      RESEND_API_KEY: 're_test_server_secret',
      FEEDBACK_TO: 'destination@example.test',
      FEEDBACK_FROM: 'Strasse <noreply@example.test>',
    });

    const json = await response.json();
    assert.equal(response.status, 200);
    assert.equal(json.success, true);
    assert.equal(requestUrl, 'https://api.resend.com/emails');
    assert.equal(requestOptions.headers.Authorization, 'Bearer re_test_server_secret');
    const email = JSON.parse(requestOptions.body);
    assert.deepEqual(email.to, ['destination@example.test']);
    assert.equal(email.reply_to, 'person@example.test');
    assert.match(email.subject, /^Feedback \d{2}\/\d{2}\/\d{4}$/);
    assert.equal(email.text, payload.message);
    assert.equal(JSON.stringify(payload).includes('destination@example.test'), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
