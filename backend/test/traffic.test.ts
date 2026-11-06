import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { NoTrafficProvider } from '../src/traffic/none.js';
import type { TrafficProvider } from '../src/traffic/provider.js';
import { mapTomTomCategory, parseTomTomIncidents, TomTomTrafficProvider } from '../src/traffic/tomtom.js';
import { makeApp } from './helpers.js';

// Fixture minimale, écrite à la main d'après la documentation TomTom (pas une réponse réelle).
const FIXTURE = {
  incidents: [
    {
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [2.35, 48.85] },
      properties: {
        id: 'abc',
        iconCategory: 1,
        events: [{ description: 'Accident', code: 401, iconCategory: 1 }],
        startTime: '2026-11-04T10:00:00Z',
        delay: 300,
      },
    },
    {
      type: 'Feature',
      geometry: { type: 'LineString', coordinates: [[2.1, 48.1], [2.2, 48.2], [2.3, 48.3]] },
      properties: { id: 'def', iconCategory: 9, events: [{ description: 'Travaux' }] },
    },
    { type: 'Feature', geometry: { type: 'Point', coordinates: [2, 48] }, properties: {} },
    { type: 'Feature', geometry: null, properties: { id: 'sans-geometrie' } },
  ],
};

describe('parseur TomTom', () => {
  it('convertit les incidents valides et ignore les entrées invalides', () => {
    const out = parseTomTomIncidents(FIXTURE);
    assert.equal(out.length, 2);
    assert.deepEqual(out[0], {
      id: 'abc', category: 'accident', lat: 48.85, lon: 2.35, source: 'tomtom',
      description: 'Accident', startTime: '2026-11-04T10:00:00Z', delayMinutes: 5,
    });
    assert.equal(out[1]?.category, 'roadwork');
    assert.equal(out[1]?.lat, 48.2); // point central de la ligne
  });
  it('tolère une réponse vide ou inattendue', () => {
    assert.deepEqual(parseTomTomIncidents(null), []);
    assert.deepEqual(parseTomTomIncidents({}), []);
    assert.deepEqual(parseTomTomIncidents({ incidents: 'x' }), []);
  });
  it('mappe les catégories', () => {
    assert.equal(mapTomTomCategory(6), 'slowdown');
    assert.equal(mapTomTomCategory(8), 'closure');
    assert.equal(mapTomTomCategory(5), 'danger');
    assert.equal(mapTomTomCategory(0), 'other');
    assert.equal(mapTomTomCategory(undefined), 'other');
  });
  it('le fournisseur interroge l\'URL attendue et signale les erreurs HTTP', async () => {
    let called = '';
    const ok = new TomTomTrafficProvider('CLE', (async (url: string) => {
      called = url;
      return new Response(JSON.stringify(FIXTURE), { status: 200 });
    }) as unknown as typeof fetch);
    const res = await ok.fetchIncidents({ minLon: 2, minLat: 48, maxLon: 3, maxLat: 49 });
    assert.equal(res.length, 2);
    assert.ok(called.includes('bbox=2%2C48%2C3%2C49'));
    const ko = new TomTomTrafficProvider('CLE', (async () => new Response('', { status: 403 })) as unknown as typeof fetch);
    await assert.rejects(() => ko.fetchIncidents({ minLon: 2, minLat: 48, maxLon: 3, maxLat: 49 }), /403/);
  });
});

describe('route /v1/traffic/incidents', () => {
  it('sans fournisseur : indisponible, aucune donnée', async () => {
    const { app } = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/v1/traffic/incidents?bbox=2,48,3,49' });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.available, false);
    assert.equal(body.provider, null);
    assert.deepEqual(body.incidents, []);
    assert.equal(new NoTrafficProvider().available, false);
  });
  it('avec un fournisseur : renvoie les incidents et met en cache', async () => {
    let calls = 0;
    const provider: TrafficProvider = {
      name: 'test', available: true,
      async fetchIncidents() {
        calls++;
        return parseTomTomIncidents(FIXTURE);
      },
    };
    const { app } = await makeApp({}, provider);
    const url = '/v1/traffic/incidents?bbox=2,48,3,49';
    const a = (await app.inject({ method: 'GET', url })).json();
    const b = (await app.inject({ method: 'GET', url })).json();
    assert.equal(a.available, true);
    assert.equal(a.provider, 'test');
    assert.equal(a.incidents.length, 2);
    assert.equal(b.incidents.length, 2);
    assert.equal(calls, 1);
  });
  it('fournisseur en panne : indisponible, jamais de données inventées', async () => {
    const provider: TrafficProvider = {
      name: 'test', available: true,
      async fetchIncidents() { throw new Error('panne'); },
    };
    const { app } = await makeApp({}, provider);
    const res = await app.inject({ method: 'GET', url: '/v1/traffic/incidents?bbox=2,48,3,49' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().available, false);
    assert.deepEqual(res.json().incidents, []);
  });
  it('refuse une zone absente ou trop grande', async () => {
    const { app } = await makeApp();
    assert.equal((await app.inject({ method: 'GET', url: '/v1/traffic/incidents' })).statusCode, 400);
    const big = await app.inject({ method: 'GET', url: '/v1/traffic/incidents?bbox=0,40,10,50' });
    assert.equal(big.statusCode, 400);
    assert.equal(big.json().error.code, 'bbox_too_large');
  });
});
