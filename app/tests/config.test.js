'use strict';

const { loadConfig, toInt } = require('../src/config');

describe('loadConfig', () => {
  it('reads every setting from the supplied environment', () => {
    const config = loadConfig({
      PORT: '3000',
      APP_VERSION: '2.0.1',
      GIT_COMMIT_SHA: 'abcdef1',
      GREETING: 'Bonjour',
      APP_ENV: 'prod',
      ENABLE_CHAOS: 'TRUE',
      SHUTDOWN_TIMEOUT_MS: '20000',
    });

    expect(config).toEqual({
      port: 3000,
      version: '2.0.1',
      commitSha: 'abcdef1',
      greeting: 'Bonjour',
      environment: 'prod',
      chaosEnabled: true,
      shutdownTimeoutMs: 20000,
    });
  });

  it('falls back to safe defaults when the environment is empty', () => {
    const config = loadConfig({});

    expect(config.port).toBe(8080);
    expect(config.version).toBe('0.0.0-dev');
    expect(config.commitSha).toBe('unknown');
    expect(config.environment).toBe('local');
    expect(config.chaosEnabled).toBe(false);
  });

  it('ignores a non-numeric PORT instead of binding to NaN', () => {
    expect(loadConfig({ PORT: 'not-a-port' }).port).toBe(8080);
    expect(toInt('42', 1)).toBe(42);
    expect(toInt(undefined, 7)).toBe(7);
  });
});
