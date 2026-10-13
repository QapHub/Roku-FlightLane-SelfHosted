import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { REPO_ROOT, runMain } from "./lib/common.mjs";
import { buildPackage } from "./build.mjs";
import { readZip } from "./lib/zip.mjs";

function runNode(args, failureMessage) {
  const result = spawnSync(process.execPath, args, { cwd: REPO_ROOT, stdio: "inherit" });
  if (result.status !== 0) throw new Error(failureMessage);
}

function brighterScriptCli() {
  const require = createRequire(path.join(REPO_ROOT, "package.json"));
  const manifestPath = require.resolve("brighterscript/package.json");
  const { bin } = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  return path.join(path.dirname(manifestPath), typeof bin === "string" ? bin : bin.bsc);
}

function listRepositoryFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return ["node_modules", "dist", "out", "tmp", ".git"].includes(entry.name)
        ? []
        : listRepositoryFiles(absolute);
    }
    return entry.isFile() ? [absolute] : [];
  });
}

runMain(() => {
  runNode(["--test"], "Node tests failed.");

  const packagePath = buildPackage({ environmentFile: ".env.example" });
  buildPackage({ environmentFile: ".env.example", screenSaver: true });

  runNode([brighterScriptCli(), "--project", "bsconfig.json"], "BrightScript validation failed.");

  let packageFiles;
  try {
    packageFiles = readZip(packagePath);
  } catch {
    throw new Error("Unable to inspect the built Roku package.");
  }
  const packageText = [...packageFiles]
    .filter(([name]) => [".brs", ".xml", ""].includes(path.extname(name)))
    .map(([, contents]) => contents.toString("utf8"))
    .join("\n")
    .toLowerCase();

  const providerMarkers = [
    "api.airplanes.live",
    "api.adsb.lol",
    "opendata.adsb.fi",
    "api.adsbdb.com",
    "basemap.nationalmap.gov",
    "geocoding.geo.census.gov",
    "api.planespotters.net",
  ];
  for (const marker of providerMarkers) {
    if (packageText.includes(marker.toLowerCase())) {
      throw new Error("The Roku package unexpectedly contains a server-only provider marker.");
    }
  }

  const blockedPlatformName = "cloud" + "flare";
  const blockedPlatformTool = "wrang" + "ler";
  for (const file of listRepositoryFiles(REPO_ROOT)) {
    if (![".brs", ".xml", ".json", ".md", ".mjs", ".txt", ""].includes(path.extname(file))) continue;
    const text = fs.readFileSync(file, "utf8").toLowerCase();
    if (text.includes(blockedPlatformName) || text.includes(blockedPlatformTool)) {
      throw new Error(`A hosted-platform reference was found in ${file}.`);
    }
  }

  console.log("Validation passed: tests, BrightScript, packages, and public-repository scans.");
});
