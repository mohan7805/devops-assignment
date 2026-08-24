'use strict';

const os = require('node:os');
const express = require('express');
const { loadConfig } = require('./config');

/**
 * Builds the Express application. The app is created as a factory so the unit
 * tests can inject a configuration without touching process.env globally.
 */
function createApp(config = loadConfig()) {
  const app = express();
  app.disable('x-powered-by');

  // Set to false by the server on SIGTERM so the ALB drains this target
  // before the process actually stops accepting connections.
  app.locals.ready = true;
  app.locals.startedAt = Date.now();

  app.use(express.json({ limit: '16kb' }));

  app.use((req, res, next) => {
    const start = process.hrtime.bigint();
    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
      // Structured logs -> stdout -> Docker awslogs driver -> CloudWatch Logs.
      console.log(
        JSON.stringify({
          level: 'info',
          msg: 'request',
          method: req.method,
          path: req.path,
          status: res.statusCode,
          duration_ms: Number(durationMs.toFixed(2)),
          hostname: os.hostname(),
          version: config.version,
        })
      );
    });
    next();
  });

  app.get('/', (req, res) => {
    res.status(200).json({ greeting: config.greeting, version: config.version });
  });

  // Target-group health check. Returns 503 once shutdown has started so the
  // ALB stops sending traffic here while in-flight requests finish.
  app.get('/health', (req, res) => {
    if (!app.locals.ready) {
      return res.status(503).json({ status: 'draining' });
    }
    return res.status(200).json({
      status: 'ok',
      uptime_s: Number(((Date.now() - app.locals.startedAt) / 1000).toFixed(3)),
    });
  });

  app.get('/info', (req, res) => {
    res.status(200).json({
      version: config.version,
      commit: config.commitSha,
      hostname: os.hostname(),
      environment: config.environment,
      greeting: config.greeting,
    });
  });

  // Only enabled when ENABLE_CHAOS=true; used to drive the ALB 5XX metric
  // above the CloudWatch alarm threshold for the alarm demonstration.
  app.get('/simulate/500', (req, res) => {
    if (!config.chaosEnabled) {
      return res.status(404).json({ error: 'not_found' });
    }
    return res.status(500).json({ error: 'simulated_server_error' });
  });

  app.use((req, res) => {
    res.status(404).json({ error: 'not_found', path: req.path });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    console.error(JSON.stringify({ level: 'error', msg: err.message }));
    res.status(500).json({ error: 'internal_server_error' });
  });

  return app;
}

module.exports = { createApp };
