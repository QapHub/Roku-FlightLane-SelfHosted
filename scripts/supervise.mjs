import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { REPO_ROOT, parseArgs, readEnvFile, resolveEnvPath, runMain } from "./lib/common.mjs";

// Runs the local service and restarts it if it exits (crash, kill, hangup) or stops
// answering /health. Ctrl+C stops both the supervisor and the service.
const HEALTH_INTERVAL_MS = 20 * 1000;
const HEALTH_TIMEOUT_MS = 5 * 1000;
const HEALTH_FAILURES_BEFORE_RESTART = 3;
const STARTUP_GRACE_MS = 15 * 1000;
const MIN_RESTART_DELAY_MS = 1000;
const MAX_RESTART_DELAY_MS = 60 * 1000;
// A run this long counts as healthy, so the next restart starts from the minimum delay.
const STABLE_RUN_MS = 5 * 60 * 1000;
const STOP_GRACE_MS = 5 * 1000;

function log(message) {
  console.log(`[supervisor ${new Date().toISOString()}] ${message}`);
}

runMain(async () => {
  const environmentFile = parseArgs()["env-file"] || ".env.local";
  const environmentPath = resolveEnvPath(environmentFile);
  const config = readEnvFile(
    environmentPath,
    `Missing ${environmentFile}. Run npm run setup first.`,
  );
  const port = Number.parseInt(config.LOCAL_API_PORT || "8787", 10) || 8787;
  const healthUrl = `http://127.0.0.1:${port}/health`;

  let child;
  let stopping = false;
  let restartDelay = MIN_RESTART_DELAY_MS;
  let startedAt = 0;
  let healthTimer;
  let healthFailures = 0;
  let restartTimer;

  function start() {
    startedAt = Date.now();
    healthFailures = 0;
    child = spawn(process.execPath, [path.join(REPO_ROOT, "server", "server.mjs")], {
      cwd: REPO_ROOT,
      env: { ...process.env, FLIGHTLANE_ENV_FILE: environmentPath },
      stdio: "inherit",
    });
    log(`Started the local service (pid ${child.pid}); checking ${healthUrl}.`);
    child.on("exit", (code, signal) => {
      clearInterval(healthTimer);
      child = undefined;
      if (stopping) return;
      const reason = signal ? `signal ${signal}` : `exit code ${code}`;
      if (Date.now() - startedAt >= STABLE_RUN_MS) restartDelay = MIN_RESTART_DELAY_MS;
      log(`The local service stopped (${reason}); restarting in ${restartDelay / 1000}s.`);
      restartTimer = setTimeout(start, restartDelay);
      restartDelay = Math.min(restartDelay * 2, MAX_RESTART_DELAY_MS);
    });
    healthTimer = setInterval(checkHealth, HEALTH_INTERVAL_MS);
  }

  async function checkHealth() {
    if (!child || Date.now() - startedAt < STARTUP_GRACE_MS) return;
    try {
      const response = await fetch(healthUrl, { signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS) });
      const health = await response.json();
      if (health?.ok !== true) throw new Error(`unexpected response (HTTP ${response.status})`);
      healthFailures = 0;
    } catch (error) {
      healthFailures += 1;
      log(`Health check ${healthFailures}/${HEALTH_FAILURES_BEFORE_RESTART} failed: ${error.message}`);
      if (healthFailures >= HEALTH_FAILURES_BEFORE_RESTART && child) {
        log("The local service is not responding; restarting it.");
        terminate(child);
      }
    }
  }

  function terminate(target) {
    target.kill("SIGTERM");
    setTimeout(() => {
      if (target.exitCode === null && target.signalCode === null) target.kill("SIGKILL");
    }, STOP_GRACE_MS).unref();
  }

  function stop(signal) {
    if (stopping) return;
    stopping = true;
    clearTimeout(restartTimer);
    clearInterval(healthTimer);
    log(`Received ${signal}; stopping.`);
    if (!child) process.exit(0);
    child.once("exit", () => process.exit(0));
    terminate(child);
  }

  process.on("SIGINT", () => stop("SIGINT"));
  process.on("SIGTERM", () => stop("SIGTERM"));
  start();
});
