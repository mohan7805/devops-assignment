'use strict';

const os = require('node:os');
const request = require('supertest');
const { createApp } = require('../src/app');

const testConfig = {
  port: 8080,
  version: '1.4.2',
  commitSha: 'a1b2c3d',
  greeting: 'Hello from the test suite',
  environment: 'test',
  chaosEnabled: false,
  shutdownTimeoutMs: 1000,
};

describe('GET /health', () => {
  it('returns 200 with status ok and a numeric uptime while the app is ready', async () => {
    const res = await request(createApp(testConfig)).get('/health');

    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(typeof res.body.uptime_s).toBe('number');
    expect(res.body.uptime_s).toBeGreaterThanOrEqual(0);
  });

  it('returns 503 once the app has been marked as draining, so the ALB removes the target', async () => {
    const app = createApp(testConfig);
    app.locals.ready = false;

    const res = await request(app).get('/health');

    expect(res.statusCode).toBe(503);
    expect(res.body.status).toBe('draining');
  });
});

describe('GET /info', () => {
  it('reports the version, the git commit SHA and the hostname', async () => {
    const res = await request(createApp(testConfig)).get('/info');

    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({
      version: '1.4.2',
      commit: 'a1b2c3d',
      hostname: os.hostname(),
      environment: 'test',
      greeting: 'Hello from the test suite',
    });
  });

  it('reflects configuration supplied through the environment rather than hardcoded values', async () => {
    const res = await request(
      createApp({ ...testConfig, version: '9.9.9', commitSha: 'deadbee', greeting: 'Ciao' })
    ).get('/info');

    expect(res.body.version).toBe('9.9.9');
    expect(res.body.commit).toBe('deadbee');
    expect(res.body.greeting).toBe('Ciao');
  });
});

describe('GET /', () => {
  it('returns the greeting supplied by configuration', async () => {
    const res = await request(createApp(testConfig)).get('/');

    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ greeting: 'Hello from the test suite', version: '1.4.2' });
  });
});

describe('GET /simulate/500 (CloudWatch alarm demo endpoint)', () => {
  it('is hidden behind a 404 when chaos mode is disabled', async () => {
    const res = await request(createApp(testConfig)).get('/simulate/500');

    expect(res.statusCode).toBe(404);
  });

  it('returns a 500 when chaos mode is explicitly enabled', async () => {
    const res = await request(createApp({ ...testConfig, chaosEnabled: true })).get('/simulate/500');

    expect(res.statusCode).toBe(500);
    expect(res.body.error).toBe('simulated_server_error');
  });
});

describe('unknown routes', () => {
  it('returns a structured 404 payload including the requested path', async () => {
    const res = await request(createApp(testConfig)).get('/does-not-exist');

    expect(res.statusCode).toBe(404);
    expect(res.body).toEqual({ error: 'not_found', path: '/does-not-exist' });
  });
});
