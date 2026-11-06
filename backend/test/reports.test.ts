import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { MAX_REPORTS_PER_HOUR } from '../src/routes/reports.js';
import type { TrafficProvider } from '../src/traffic/provider.js';
import { makeApp, newInstallId } from './helpers.js';

const BBOX = '2.2,48.8,2.5,48.9';
const post = (app: Awaited<ReturnType<typeof makeApp>>['app'], installId: string | undefined, payload: unknown, url = '/v1/reports') =>
  app.inject({ method: 'POST', url, headers: installId ? { 'x-install-id': installId } : {}, payload: payload as object });

describe('signalements communautaires', () => {
  it('création puis lecture dans la zone', async () => {
    const { app } = await makeApp();
    const res = await post(app, newInstallId(), { type: 'accident', lat: 48.85, lon: 2.35 });
    assert.equal(res.statusCode, 201);
    const r = res.json();
    assert.equal(r.status, 'active');
    assert.equal(r.confirmations, 0);
    assert.ok(r.reliability > 0 && r.reliability < 1);
    assert.equal('reporterHash' in r, false);
    assert.equal(new Date(r.expiresAt).getTime() - new Date(r.createdAt).getTime(), 2 * 3600_000);

    const list = (await app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json();
    assert.equal(list.reports.length, 1);
    const out = (await app.inject({ method: 'GET', url: '/v1/reports?bbox=5,40,5.2,40.2' })).json();
    assert.equal(out.reports.length, 0);
  });

  it('exige un X-Install-Id valide', async () => {
    const { app } = await makeApp();
    for (const id of [undefined, 'pas-un-uuid']) {
      const res = await post(app, id, { type: 'accident', lat: 48.85, lon: 2.35 });
      assert.equal(res.statusCode, 400);
      assert.equal(res.json().error.code, 'missing_install_id');
    }
  });

  it('validation stricte : type, coordonnées, (0, 0)', async () => {
    const { app } = await makeApp();
    const id = newInstallId();
    for (const bad of [
      { type: 'ovni', lat: 48, lon: 2 },
      { type: 'accident', lat: 91, lon: 2 },
      { type: 'accident', lat: 48, lon: 181 },
      { type: 'accident', lat: '48', lon: 2 },
      { type: 'accident', lat: 0, lon: 0 },
      {},
    ]) {
      assert.equal((await post(app, id, bad)).statusCode, 400, JSON.stringify(bad));
    }
  });

  it('un doublon (même type, < 150 m) est fusionné comme une confirmation', async () => {
    const { app } = await makeApp();
    const first = (await post(app, newInstallId(), { type: 'accident', lat: 48.85, lon: 2.35 })).json();
    const dup = await post(app, newInstallId(), { type: 'accident', lat: 48.8506, lon: 2.3503 });
    assert.equal(dup.statusCode, 200);
    assert.equal(dup.json().id, first.id);
    assert.equal(dup.json().confirmations, 1);
    // Autre type au même endroit : nouveau signalement.
    const other = await post(app, newInstallId(), { type: 'roadwork', lat: 48.85, lon: 2.35 });
    assert.equal(other.statusCode, 201);
    // Le même auteur ne gonfle pas son propre signalement.
    const same = newInstallId();
    const mine = (await post(app, same, { type: 'danger', lat: 48.86, lon: 2.36 })).json();
    const again = await post(app, same, { type: 'danger', lat: 48.86, lon: 2.36 });
    assert.equal(again.json().id, mine.id);
    assert.equal(again.json().confirmations, 0);
  });

  it('confirmation : un seul vote par installation, prolonge la validité', async () => {
    const { app } = await makeApp();
    const created = (await post(app, newInstallId(), { type: 'accident', lat: 48.85, lon: 2.35 })).json();
    const voter = newInstallId();
    const c1 = await post(app, voter, {}, `/v1/reports/${created.id}/confirm`);
    assert.equal(c1.statusCode, 200);
    assert.equal(c1.json().confirmations, 1);
    assert.ok(new Date(c1.json().expiresAt) > new Date(created.expiresAt));
    const c2 = await post(app, voter, {}, `/v1/reports/${created.id}/confirm`);
    assert.equal(c2.statusCode, 409);
    assert.equal(c2.json().error.code, 'already_voted');
    const rej = await post(app, voter, {}, `/v1/reports/${created.id}/reject`);
    assert.equal(rej.statusCode, 409);
  });

  it('l\'auteur ne peut pas voter pour son propre signalement', async () => {
    const { app } = await makeApp();
    const author = newInstallId();
    const created = (await post(app, author, { type: 'accident', lat: 48.85, lon: 2.35 })).json();
    const res = await post(app, author, {}, `/v1/reports/${created.id}/confirm`);
    assert.equal(res.statusCode, 409);
  });

  it('masquage automatique après suffisamment de rejets', async () => {
    const { app } = await makeApp();
    const created = (await post(app, newInstallId(), { type: 'obstacle', lat: 48.85, lon: 2.35 })).json();
    let last;
    for (let i = 0; i < 3; i++) last = await post(app, newInstallId(), {}, `/v1/reports/${created.id}/reject`);
    assert.equal(last?.json().status, 'hidden');
    const list = (await app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json();
    assert.equal(list.reports.length, 0);
    const late = await post(app, newInstallId(), {}, `/v1/reports/${created.id}/confirm`);
    assert.equal(late.statusCode, 410);
  });

  it('expiration automatique : plus listé, vote refusé', async () => {
    const { app, clock, reports } = await makeApp();
    const created = (await post(app, newInstallId(), { type: 'slowdown', lat: 48.85, lon: 2.35 })).json();
    clock.advance(46 * 60_000);
    const list = (await app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json();
    assert.equal(list.reports.length, 0);
    const vote = await post(app, newInstallId(), {}, `/v1/reports/${created.id}/confirm`);
    assert.equal(vote.statusCode, 410);
    assert.equal(await reports.expireDue(clock.now()), 1);
    assert.equal(await reports.purgeExpiredBefore(new Date(clock.now().getTime() + 1_000_000_000)), 1);
  });

  it('signalement introuvable', async () => {
    const { app } = await makeApp();
    const res = await post(app, newInstallId(), {}, '/v1/reports/3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e/confirm');
    assert.equal(res.statusCode, 404);
    const bad = await post(app, newInstallId(), {}, '/v1/reports/pas-un-id/confirm');
    assert.equal(bad.statusCode, 404);
  });

  it('bbox obligatoire et limitée', async () => {
    const { app } = await makeApp();
    assert.equal((await app.inject({ method: 'GET', url: '/v1/reports' })).statusCode, 400);
    const big = await app.inject({ method: 'GET', url: '/v1/reports?bbox=0,40,10,50' });
    assert.equal(big.json().error.code, 'bbox_too_large');
  });

  it('limitation par installation : trop de signalements en une heure', async () => {
    const { app } = await makeApp({ RATE_LIMIT_MAX: '10000' });
    const id = newInstallId();
    let last = 201;
    for (let i = 0; i < MAX_REPORTS_PER_HOUR + 1; i++) {
      // Positions espacées pour éviter la fusion en doublon.
      last = (await post(app, id, { type: 'other', lat: 45 + i * 0.01, lon: 3 })).statusCode;
    }
    assert.equal(last, 429);
  });

  it('un incident externe concordant augmente la fiabilité', async () => {
    const withIncident: TrafficProvider = {
      name: 'test', available: true,
      async fetchIncidents() {
        return [{ id: 'x', category: 'accident', lat: 48.8501, lon: 2.3501, source: 'test' }];
      },
    };
    const a = await makeApp();
    const b = await makeApp({}, withIncident);
    await post(a.app, newInstallId(), { type: 'accident', lat: 48.85, lon: 2.35 });
    await post(b.app, newInstallId(), { type: 'accident', lat: 48.85, lon: 2.35 });
    const ra = (await a.app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json().reports[0];
    const rb = (await b.app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json().reports[0];
    assert.ok(rb.reliability > ra.reliability);
  });
});

describe('modération', () => {
  it('routes absentes (404) sans ADMIN_TOKEN', async () => {
    const { app } = await makeApp();
    assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/reports' })).statusCode, 404);
  });

  it('exige le jeton, puis masque, restaure et supprime', async () => {
    const { app } = await makeApp({ ADMIN_TOKEN: 'jeton-admin-de-test' });
    const created = (await post(app, newInstallId(), { type: 'closure', lat: 48.85, lon: 2.35 })).json();
    assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/reports?status=active' })).statusCode, 401);
    const h = { authorization: 'Bearer jeton-admin-de-test' };
    assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/reports', headers: { authorization: 'Bearer faux' } })).statusCode, 401);

    const active = (await app.inject({ method: 'GET', url: '/v1/admin/reports?status=active', headers: h })).json();
    assert.equal(active.reports.length, 1);

    const hide = await app.inject({ method: 'POST', url: `/v1/admin/reports/${created.id}/moderate`, headers: h, payload: { action: 'hide' } });
    assert.equal(hide.json().status, 'hidden');
    assert.equal((await app.inject({ method: 'GET', url: `/v1/reports?bbox=${BBOX}` })).json().reports.length, 0);

    const restore = await app.inject({ method: 'POST', url: `/v1/admin/reports/${created.id}/moderate`, headers: h, payload: { action: 'restore' } });
    assert.equal(restore.json().status, 'active');

    const del = await app.inject({ method: 'POST', url: `/v1/admin/reports/${created.id}/moderate`, headers: h, payload: { action: 'delete' } });
    assert.equal(del.statusCode, 204);
    const gone = await app.inject({ method: 'POST', url: `/v1/admin/reports/${created.id}/moderate`, headers: h, payload: { action: 'hide' } });
    assert.equal(gone.statusCode, 404);
    const bad = await app.inject({ method: 'POST', url: `/v1/admin/reports/${created.id}/moderate`, headers: h, payload: { action: 'x' } });
    assert.equal(bad.statusCode, 400);
  });
});
