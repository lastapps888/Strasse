import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { AppError } from '../src/errors.js';
import { decryptString, encryptString, hashInstallId } from '../src/services/crypto.js';
import { findDuplicate } from '../src/services/dedupe.js';
import { BASE_DURATION_MS, computeExpiry, shouldAutoHide } from '../src/services/expiry.js';
import { bboxAround, haversineMeters, parseBbox } from '../src/services/geo.js';
import { hashPassword, verifyPassword } from '../src/services/password.js';
import { computeReliability } from '../src/services/reliability.js';
import { ACCESS_TTL_SECONDS, signAccessToken, verifyAccessToken } from '../src/services/tokens.js';
import { loadConfig } from '../src/config.js';

describe('géographie', () => {
  it('haversine : Paris → Lyon ≈ 392 km', () => {
    const d = haversineMeters(48.8566, 2.3522, 45.764, 4.8357);
    assert.ok(d > 388_000 && d < 396_000, `distance ${d}`);
  });
  it('haversine : distance nulle pour un même point', () => {
    assert.equal(haversineMeters(10, 10, 10, 10), 0);
  });
  it('parseBbox accepte une zone valide', () => {
    assert.deepEqual(parseBbox('2.2,48.8,2.5,48.9'), { minLon: 2.2, minLat: 48.8, maxLon: 2.5, maxLat: 48.9 });
  });
  it('parseBbox refuse une zone absente, mal formée, inversée ou trop grande', () => {
    for (const bad of [undefined, 'a,b,c,d', '1,2,3', '3,48,2,49']) {
      assert.throws(() => parseBbox(bad), (e: unknown) => e instanceof AppError && e.code === 'invalid_bbox');
    }
    assert.throws(() => parseBbox('0,40,5,45'), (e: unknown) => e instanceof AppError && e.code === 'bbox_too_large');
  });
  it('bboxAround contient bien le point', () => {
    const b = bboxAround(48.85, 2.35, 150);
    assert.ok(b.minLat < 48.85 && b.maxLat > 48.85 && b.minLon < 2.35 && b.maxLon > 2.35);
  });
});

describe('expiration', () => {
  const t0 = new Date('2026-11-04T12:00:00Z');
  it('durées de base par type', () => {
    assert.equal(computeExpiry('accident', t0, 0).getTime() - t0.getTime(), 2 * 3600_000);
    assert.equal(computeExpiry('slowdown', t0, 0).getTime() - t0.getTime(), 45 * 60_000);
    assert.equal(computeExpiry('roadwork', t0, 0).getTime() - t0.getTime(), 24 * 3600_000);
  });
  it('chaque confirmation prolonge de 25 % de la durée de base', () => {
    const base = BASE_DURATION_MS.accident;
    assert.equal(computeExpiry('accident', t0, 2).getTime() - t0.getTime(), base * 1.5);
  });
  it('la prolongation est plafonnée à 3× la durée de base', () => {
    const base = BASE_DURATION_MS.danger;
    assert.equal(computeExpiry('danger', t0, 100).getTime() - t0.getTime(), base * 3);
  });
  it('masquage automatique quand rejets ≥ confirmations + 3', () => {
    assert.equal(shouldAutoHide(0, 2), false);
    assert.equal(shouldAutoHide(0, 3), true);
    assert.equal(shouldAutoHide(2, 4), false);
    assert.equal(shouldAutoHide(2, 5), true);
  });
});

describe('fiabilité', () => {
  const created = new Date('2026-11-04T12:00:00Z');
  const expires = new Date('2026-11-04T14:00:00Z');
  const at = (minutes: number) => new Date(created.getTime() + minutes * 60_000);
  const base = { createdAt: created, expiresAt: expires };

  it('reste strictement entre 0 et 1', () => {
    const high = computeReliability({ ...base, now: created, confirmations: 500, rejections: 0, externalCorroboration: true });
    const low = computeReliability({ ...base, now: expires, confirmations: 0, rejections: 500 });
    assert.ok(high < 1 && high > 0.9);
    assert.ok(low > 0 && low < 0.1);
  });
  it('augmente avec les confirmations et diminue avec les rejets', () => {
    const r = (c: number, j: number) => computeReliability({ ...base, now: at(10), confirmations: c, rejections: j });
    assert.ok(r(3, 0) > r(0, 0));
    assert.ok(r(0, 2) < r(0, 0));
  });
  it('diminue avec l\'ancienneté', () => {
    const r = (m: number) => computeReliability({ ...base, now: at(m), confirmations: 1, rejections: 0 });
    assert.ok(r(5) > r(60));
    assert.ok(r(60) > r(115));
  });
  it('augmente quand un incident externe concorde', () => {
    const r = (ext: boolean) =>
      computeReliability({ ...base, now: at(10), confirmations: 0, rejections: 0, externalCorroboration: ext });
    assert.ok(r(true) > r(false));
  });
});

describe('doublons', () => {
  const now = new Date('2026-11-04T12:00:00Z');
  const future = new Date('2026-11-04T13:00:00Z');
  const c = (id: string, lat: number, lon: number, extra = {}) => ({
    id, type: 'accident' as const, lat, lon, expiresAt: future, status: 'active', ...extra,
  });
  it('trouve le plus proche à moins de 150 m, même type, actif', () => {
    const found = findDuplicate([c('far', 48.8575, 2.3522), c('near', 48.8567, 2.3523)], 'accident', 48.8566, 2.3522, now);
    assert.equal(found?.id, 'near');
  });
  it('ignore un autre type, un signalement expiré ou masqué, ou trop éloigné', () => {
    assert.equal(findDuplicate([c('a', 48.8566, 2.3522, { type: 'roadwork' })], 'accident', 48.8566, 2.3522, now), undefined);
    assert.equal(findDuplicate([c('b', 48.8566, 2.3522, { expiresAt: now })], 'accident', 48.8566, 2.3522, now), undefined);
    assert.equal(findDuplicate([c('c', 48.8566, 2.3522, { status: 'hidden' })], 'accident', 48.8566, 2.3522, now), undefined);
    assert.equal(findDuplicate([c('d', 48.86, 2.3522)], 'accident', 48.8566, 2.3522, now), undefined);
  });
});

describe('mots de passe', () => {
  it('hachage puis vérification', async () => {
    const h = await hashPassword('correct horse battery');
    assert.ok(h.startsWith('scrypt$'));
    assert.equal(await verifyPassword('correct horse battery', h), true);
    assert.equal(await verifyPassword('mauvais', h), false);
  });
  it('deux hachages du même mot de passe diffèrent (sel aléatoire)', async () => {
    assert.notEqual(await hashPassword('identique-identique'), await hashPassword('identique-identique'));
  });
  it('un hachage mal formé est refusé sans exception', async () => {
    assert.equal(await verifyPassword('x', 'n-importe-quoi'), false);
  });
});

describe('chiffrement AES-256-GCM', () => {
  const key = Buffer.alloc(32, 7);
  it('aller-retour', () => {
    const enc = encryptString('{"nom":"Café de la gare"}', key);
    assert.ok(enc.startsWith('enc:v1:'));
    assert.equal(decryptString(enc, key), '{"nom":"Café de la gare"}');
  });
  it('un chiffrement est non déterministe', () => {
    assert.notEqual(encryptString('a', key), encryptString('a', key));
  });
  it('une mauvaise clé ou une altération échoue', () => {
    const enc = encryptString('secret', key);
    assert.throws(() => decryptString(enc, Buffer.alloc(32, 9)));
    const tampered = enc.slice(0, -2) + (enc.endsWith('AA') ? 'BB' : 'AA');
    assert.throws(() => decryptString(tampered, key));
  });
  it('une valeur non chiffrée est renvoyée telle quelle', () => {
    assert.equal(decryptString('{"a":1}', null), '{"a":1}');
  });
  it('le pseudonyme d\'installation est stable et dépend du sel', () => {
    const id = '3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e';
    assert.equal(hashInstallId(id, 'sel1'), hashInstallId(id, 'sel1'));
    assert.notEqual(hashInstallId(id, 'sel1'), hashInstallId(id, 'sel2'));
    assert.ok(!hashInstallId(id, 'sel1').includes(id));
  });
});

describe('jetons d\'accès', () => {
  const secret = 'un-secret-de-test-0123456789abcdef0123456789';
  it('signature puis vérification', async () => {
    const t = await signAccessToken('user-1', secret);
    assert.equal(await verifyAccessToken(t, secret), 'user-1');
  });
  it('refuse un mauvais secret, un jeton expiré ou du texte quelconque', async () => {
    const t = await signAccessToken('user-1', secret);
    assert.equal(await verifyAccessToken(t, 'autre-secret-0123456789abcdef0123456789'), null);
    const old = await signAccessToken('user-1', secret, new Date(Date.now() - (ACCESS_TTL_SECONDS + 60) * 1000));
    assert.equal(await verifyAccessToken(old, secret), null);
    assert.equal(await verifyAccessToken('pas-un-jwt', secret), null);
  });
});

describe('configuration', () => {
  it('refuse de démarrer en production sans secrets', () => {
    assert.throws(() => loadConfig({ NODE_ENV: 'production' }), /JWT_SECRET/);
    assert.throws(
      () => loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(32) }),
      /SERVER_SALT/,
    );
    assert.throws(
      () => loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(32), SERVER_SALT: 'y'.repeat(32) }),
      /DATABASE_URL/,
    );
  });
  it('accepte une configuration de production complète', () => {
    const c = loadConfig({
      NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(32), SERVER_SALT: 'y'.repeat(32), DATABASE_URL: 'postgres://u:p@h/db',
    });
    assert.equal(c.NODE_ENV, 'production');
  });
  it('refuse une clé de chiffrement de mauvaise taille', () => {
    assert.throws(() => loadConfig({ NODE_ENV: 'test', SYNC_ENCRYPTION_KEY: 'AAAA' }), /32 octets/);
  });
});
