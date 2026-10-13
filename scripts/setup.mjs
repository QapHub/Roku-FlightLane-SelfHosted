import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { REPO_ROOT, runMain } from "./lib/common.mjs";

runMain(() => {
  const examplePath = path.join(REPO_ROOT, ".env.example");
  const environmentPath = path.join(REPO_ROOT, ".env.local");

  if (!fs.existsSync(environmentPath)) {
    fs.copyFileSync(examplePath, environmentPath);
    console.log("Created .env.local from the safe example.");
  } else {
    console.log(".env.local already exists; it was not changed.");
  }

  const addresses = new Set();
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family !== "IPv4" && entry.family !== 4) continue;
      if (entry.internal || entry.address.startsWith("127.") || entry.address.startsWith("169.254.")) continue;
      addresses.add(entry.address);
    }
  }

  if (addresses.size > 0) {
    console.log("");
    console.log("Possible computer address for FLIGHTLANE_API_URL:");
    for (const address of addresses) {
      console.log(`  http://${address}:8787`);
    }
  } else {
    console.log("Automatic private-network address detection was unavailable.");
  }

  console.log("");
  console.log("Next:");
  console.log("  1. Edit .env.local and replace both example IP addresses.");
  console.log("  2. Add your Google API key(s) and optional FlightAware key.");
  console.log("  3. Run npm run api and leave that terminal open.");
  console.log("  4. In a second terminal, run npm run deploy.");
});
