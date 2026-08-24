'use strict';

const { createApp } = require('./app');
const { loadConfig } = require('./config');

const config = loadConfig();
const app = createApp(config);

const server = app.listen(config.port, '0.0.0.0', () => {
  console.log(
    JSON.stringify({
      level: 'info',
      msg: 'server_started',
      port: config.port,
      version: config.version,
      commit: config.commitSha,
      environment: config.environment,
    })
  );
});

// Keep-alive must outlive the ALB idle timeout (60s) to avoid 502s on races.
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;

/**
 * Graceful shutdown: this is what makes rolling deployments zero-downtime.
 * 1. Flip /health to 503 so the ALB deregisters this target.
 * 2. Wait for the deregistration delay, then stop accepting new connections.
 * 3. Exit once in-flight requests have completed.
 */
function shutdown(signal) {
  console.log(JSON.stringify({ level: 'info', msg: 'shutdown_started', signal }));
  app.locals.ready = false;

  setTimeout(() => {
    server.close(() => {
      console.log(JSON.stringify({ level: 'info', msg: 'shutdown_complete' }));
      process.exit(0);
    });
  }, Math.min(config.shutdownTimeoutMs, 10000)).unref();

  setTimeout(() => {
    console.error(JSON.stringify({ level: 'error', msg: 'shutdown_forced' }));
    process.exit(1);
  }, config.shutdownTimeoutMs + 5000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = server;
