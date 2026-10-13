import process from "node:process";
import { parseArgs, readEnvFile, resolveEnvPath, runMain } from "./lib/common.mjs";

runMain(async () => {
  const environmentFile = parseArgs()["env-file"] || ".env.local";
  const config = readEnvFile(
    resolveEnvPath(environmentFile),
    `Missing ${environmentFile}. Run npm run setup first.`,
  );
  const serviceUrl = String(config.FLIGHTLANE_API_URL || "").replace(/\/+$/, "");
  const rokuIp = String(config.ROKU_DEVICE_IP || "").trim();
  const problems = [];

  console.log("Flight Lane self-hosted diagnostics");
  console.log("");

  const nodeMajor = Number.parseInt(process.versions.node, 10);
  if (nodeMajor < 20) {
    problems.push("Node.js 20 or newer is required.");
  } else {
    console.log(`[OK] Node.js ${process.version}`);
  }

  if (!serviceUrl) {
    problems.push("FLIGHTLANE_API_URL is missing.");
  } else if (/192\.168\.1\.100/.test(serviceUrl)) {
    problems.push("FLIGHTLANE_API_URL still contains the example computer address.");
  } else {
    try {
      const response = await fetch(`${serviceUrl}/health`, { signal: AbortSignal.timeout(5000) });
      const health = await response.json();
      if (health.ok === true) {
        console.log("[OK] Local service responded.");
        console.log(
          `     Maps=${health.features.satelliteMaps}, address lookup=${health.features.addressLookup}, flight details=${health.features.flightDetails}, photos=${health.features.aircraftPhotos}`,
        );
        const spend = health.flightAwareSpend;
        if (!spend) {
          console.log("     FlightAware: off (no key; nothing is sent to FlightAware)");
        } else if (spend.state === "limit" || spend.state === "unavailable") {
          problems.push(
            spend.state === "limit"
              ? `FlightAware spend $${spend.monthToDateCost} reached the $${spend.limit} limit; live status is paused.`
              : "FlightAware usage could not be read; live status is paused. Check FLIGHTAWARE_API_KEY.",
          );
        } else {
          const cost = spend.monthToDateCost === undefined ? "checking" : `$${spend.monthToDateCost}`;
          console.log(
            `     FlightAware: ${spend.state}, ${cost} this month (warning $${spend.warning}, limit $${spend.limit})`,
          );
        }
      } else {
        problems.push("The local service health response was invalid.");
      }
    } catch {
      problems.push("The local service did not respond. Start it with npm run api.");
    }
  }

  if (!rokuIp) {
    problems.push("ROKU_DEVICE_IP is missing.");
  } else if (rokuIp === "192.168.1.50") {
    problems.push("ROKU_DEVICE_IP still contains the example Roku address.");
  } else {
    try {
      const response = await fetch(`http://${rokuIp}`, { signal: AbortSignal.timeout(5000) });
      if (response.ok) {
        console.log(`[OK] Roku developer installer responded with HTTP ${response.status}.`);
      } else {
        console.log("[OK] Roku developer installer is reachable and requested authentication.");
      }
    } catch {
      problems.push("The Roku developer installer was not reachable.");
    }
  }

  console.log("");
  if (problems.length === 0) {
    console.log("Diagnostics passed.");
    return;
  }

  console.log("Fix these items:");
  for (const problem of problems) {
    console.log(`  - ${problem}`);
  }
  process.exitCode = 1;
});
