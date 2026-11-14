import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { describe, it } from 'node:test';
import { bearer, makeApp, register } from './helpers.js';

describe('santé et erreurs', () => {
  it('GET /v1/health', async () => {
    const { app } = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/v1/health' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().status, 'ok');
  });
  it('route inconnue : format d\'erreur uniforme', async () => {
    const { app } = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/v1/inconnu' });
    assert.equal(res.statusCode, 404);
    assert.equal(res.json().error.code, 'not_found');
  });
  it('entrée invalide : 400 avec message en français', async () => {
    const { app } = await makeApp();
    const res = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: 'pas-un-email', password: 'court' } });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, 'validation_error');
    assert.ok(typeof res.json().error.message === 'string');
  });
  it('limitation de débit par IP', async () => {
    const { app } = await makeApp({ RATE_LIMIT_MAX: '3' });
    const codes: number[] = [];
    for (let i = 0; i < 5; i++) codes.push((await app.inject({ method: 'GET', url: '/v1/health' })).statusCode);
    assert.deepEqual(codes, [200, 200, 200, 429, 429]);
  });
});

describe('comptes', () => {
  it('inscription, connexion, doublon et mauvais mot de passe', async () => {
    const { app } = await makeApp();
    const { res, body } = await register(app, 'Ada@Example.org');
    assert.equal(res.statusCode, 201);
    assert.equal(body.user.email, 'ada@example.org');
    assert.ok(body.accessToken && body.refreshToken);

    const dup = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: 'ada@example.org', password: 'un-mot-de-passe-solide' } });
    assert.equal(dup.statusCode, 409);
    assert.equal(dup.json().error.code, 'email_taken');

    const ok = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'ada@example.org', password: 'un-mot-de-passe-solide' } });
    assert.equal(ok.statusCode, 200);
    const ko = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'ada@example.org', password: 'mauvais-mot-de-passe' } });
    assert.equal(ko.statusCode, 401);
    const unknown = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'inconnu@example.org', password: 'mauvais-mot-de-passe' } });
    assert.equal(unknown.statusCode, 401);
    assert.equal(unknown.json().error.code, ko.json().error.code);
  });

  it('rotation des jetons de rafraîchissement et détection de réutilisation', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const r1 = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: body.refreshToken } });
    assert.equal(r1.statusCode, 200);
    const second = r1.json() as { accessToken: string; refreshToken: string };
    assert.notEqual(second.refreshToken, body.refreshToken);

    // Réutilisation de l'ancien jeton : refusée, et toute la famille est révoquée.
    const reuse = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: body.refreshToken } });
    assert.equal(reuse.statusCode, 401);
    assert.equal(reuse.json().error.code, 'token_reuse_detected');
    const after = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: second.refreshToken } });
    assert.equal(after.statusCode, 401);
  });

  it('jeton de rafraîchissement expiré ou inconnu', async () => {
    const { app, clock } = await makeApp();
    const { body } = await register(app);
    const unknown = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: 'x'.repeat(43) } });
    assert.equal(unknown.statusCode, 401);
    clock.advance(31 * 24 * 3600_000);
    const expired = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: body.refreshToken } });
    assert.equal(expired.statusCode, 401);
  });

  it('déconnexion révoque la session', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const out = await app.inject({ method: 'POST', url: '/v1/auth/logout', headers: bearer(body.accessToken), payload: { refreshToken: body.refreshToken } });
    assert.equal(out.statusCode, 204);
    const r = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: body.refreshToken } });
    assert.equal(r.statusCode, 401);
  });

  it('routes protégées sans jeton ou avec jeton invalide', async () => {
    const { app } = await makeApp();
    assert.equal((await app.inject({ method: 'GET', url: '/v1/sync/pull' })).statusCode, 401);
    assert.equal((await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: bearer('xxx') })).statusCode, 401);
    assert.equal((await app.inject({ method: 'DELETE', url: '/v1/account' })).statusCode, 401);
  });

  it('suppression du compte supprime aussi les données et les sessions', async () => {
    const { app, users, tokens, sync } = await makeApp();
    const { body } = await register(app);
    const fav = { id: randomUUID(), updatedAt: '2026-11-04T10:00:00.000Z', deleted: false, name: 'Maison', lat: 48.85, lon: 2.35, kind: 'home' };
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: bearer(body.accessToken), payload: { favorites: [fav] } });
    assert.equal(sync.countForUser(body.user.id), 1);
    const del = await app.inject({ method: 'DELETE', url: '/v1/account', headers: bearer(body.accessToken) });
    assert.equal(del.statusCode, 204);
    assert.equal(users.size, 0);
    assert.equal(tokens.countForUser(body.user.id), 0);
    assert.equal(sync.countForUser(body.user.id), 0);
  });
});

describe('synchronisation', () => {
  const fav = (over: Record<string, unknown> = {}) => ({
    id: randomUUID(), updatedAt: '2026-11-04T10:00:00.000Z', deleted: false,
    name: 'Café', lat: 48.85, lon: 2.35, kind: 'place', ...over,
  });

  it('push puis pull restituent les éléments, champs supplémentaires inclus', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const f = fav({ note: 'Très bon expresso' });
    const col = { id: randomUUID(), updatedAt: '2026-11-04T10:00:00.000Z', deleted: false, name: 'Vacances', position: 0 };
    const prefs = { data: { theme: 'sombre' }, updatedAt: '2026-11-04T10:00:00.000Z' };
    const push = await app.inject({ method: 'POST', url: '/v1/sync/push', headers: bearer(body.accessToken), payload: { favorites: [f], collections: [col], preferences: prefs } });
    assert.equal(push.statusCode, 200);
    assert.deepEqual(push.json().applied, { favorites: 1, collections: 1, trips: 0, preferences: true });

    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: bearer(body.accessToken) })).json();
    assert.deepEqual(pull.favorites, [f]);
    assert.deepEqual(pull.collections, [col]);
    assert.deepEqual(pull.trips, []);
    assert.deepEqual(pull.preferences, prefs);
    assert.ok(pull.serverTime);
  });

  it('dernière écriture gagnante : un élément plus ancien est ignoré', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const id = randomUUID();
    const h = bearer(body.accessToken);
    const push = (item: Record<string, unknown>) =>
      app.inject({ method: 'POST', url: '/v1/sync/push', headers: h, payload: { favorites: [item] } });
    await push(fav({ id, name: 'Nouveau', updatedAt: '2026-11-04T12:00:00.000Z' }));
    const old = await push(fav({ id, name: 'Ancien', updatedAt: '2026-11-04T09:00:00.000Z' }));
    assert.equal(old.json().applied.favorites, 0);
    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: h })).json();
    assert.equal(pull.favorites[0].name, 'Nouveau');
  });

  it('les suppressions (tombstones) sont conservées et propagées', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const h = bearer(body.accessToken);
    const id = randomUUID();
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: h, payload: { favorites: [fav({ id })] } });
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: h, payload: { favorites: [fav({ id, deleted: true, updatedAt: '2026-11-04T11:00:00.000Z' })] } });
    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: h })).json();
    assert.equal(pull.favorites.length, 1);
    assert.equal(pull.favorites[0].deleted, true);
  });

  it('pull?since ne renvoie que les éléments plus récents', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const h = bearer(body.accessToken);
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: h, payload: { favorites: [fav({ name: 'A', updatedAt: '2026-11-04T08:00:00.000Z' }), fav({ name: 'B', updatedAt: '2026-11-04T12:00:00.000Z' })] } });
    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull?since=2026-11-04T10:00:00.000Z', headers: h })).json();
    assert.deepEqual(pull.favorites.map((f: { name: string }) => f.name), ['B']);
    const bad = await app.inject({ method: 'GET', url: '/v1/sync/pull?since=hier', headers: h });
    assert.equal(bad.statusCode, 400);
  });

  it('les données de deux comptes sont isolées', async () => {
    const { app } = await makeApp();
    const a = (await register(app, 'a@example.org')).body;
    const b = (await register(app, 'b@example.org')).body;
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: bearer(a.accessToken), payload: { favorites: [fav()] } });
    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: bearer(b.accessToken) })).json();
    assert.deepEqual(pull.favorites, []);
  });

  it('refuse un élément sans id/updatedAt/deleted valides', async () => {
    const { app } = await makeApp();
    const { body } = await register(app);
    const res = await app.inject({ method: 'POST', url: '/v1/sync/push', headers: bearer(body.accessToken), payload: { favorites: [{ id: 'pas-un-uuid', updatedAt: 'x', deleted: 'non' }] } });
    assert.equal(res.statusCode, 400);
  });

  it('chiffrement au repos : la base ne contient pas le texte en clair, le pull le restitue', async () => {
    const key = Buffer.alloc(32, 5).toString('base64');
    const { app, sync } = await makeApp({ SYNC_ENCRYPTION_KEY: key });
    const { body } = await register(app);
    const f = fav({ name: 'Adresse très privée' });
    await app.inject({ method: 'POST', url: '/v1/sync/push', headers: bearer(body.accessToken), payload: { favorites: [f] } });
    const rows = await sync.list(body.user.id, 'favorites');
    assert.ok(rows[0]?.data.startsWith('enc:v1:'));
    assert.ok(!rows[0]?.data.includes('très privée'));
    const pull = (await app.inject({ method: 'GET', url: '/v1/sync/pull', headers: bearer(body.accessToken) })).json();
    assert.deepEqual(pull.favorites, [f]);
  });
});
