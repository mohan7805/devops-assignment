'use strict';

/**
 * Every piece of runtime configuration comes from an environment variable.
 * Nothing is hardcoded, and no secret is ever committed to the repository:
 * in AWS the values below are injected by user-data after being read from
 * SSM Parameter Store (see terraform/modules/compute/user_data.sh.tftpl).
 */

function toInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function loadConfig(env = process.env) {
  return {
    // Port the HTTP server binds to.
    port: toInt(env.PORT, 8080),
    // Semantic version of the application, stamped at build time.
    version: env.APP_VERSION || '0.0.0-dev',
    // Short git SHA the image was built from, passed as a Docker build arg.
    commitSha: env.GIT_COMMIT_SHA || 'unknown',
    // Greeting text – sourced from SSM Parameter Store in AWS.
    greeting: env.GREETING || 'Hello from the DevOps assignment API',
    // Deployment environment name (local, dev, prod...).
    environment: env.APP_ENV || 'local',
    // Enables the /simulate/500 endpoint used to demonstrate the CloudWatch alarm.
    chaosEnabled: String(env.ENABLE_CHAOS || 'false').toLowerCase() === 'true',
    // Grace period, in ms, given to in-flight requests on SIGTERM (zero-downtime).
    shutdownTimeoutMs: toInt(env.SHUTDOWN_TIMEOUT_MS, 15000),
  };
}

module.exports = { loadConfig, toInt };
