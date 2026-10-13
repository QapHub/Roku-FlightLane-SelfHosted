import { spawn } from "node:child_process";
import process from "node:process";
import {
  parseArgs,
  promptHidden,
  readEnvFile,
  requireRokuIp,
  resolveEnvPath,
  runMain,
} from "./lib/common.mjs";
import { buildPackage } from "./build.mjs";

function curlConfigString(value) {
  return `"${value.replace(/[\\"]/g, "\\$&")}"`;
}

runMain(async () => {
  const environmentFile = parseArgs()["env-file"] || ".env.local";
  const packagePath = buildPackage({ environmentFile });
  const config = readEnvFile(resolveEnvPath(environmentFile));
  const rokuIp = requireRokuIp(config, environmentFile);

  // Use a saved developer password when present; otherwise ask without echoing it.
  const savedPassword = String(config.ROKU_DEVELOPER_PASSWORD ?? "");
  const password = savedPassword || (await promptHidden("Roku developer password: "));
  if (savedPassword) {
    console.log(`Using the Roku developer password from ${environmentFile}.`);
  }

  // Credentials go to curl on stdin so they never appear in the process list.
  const exitCode = await new Promise((resolve, reject) => {
    const curl = spawn(
      "curl",
      [
        "--config",
        "-",
        "--fail-with-body",
        "--silent",
        "--show-error",
        "--digest",
        "--form",
        "mysubmit=Install",
        "--form",
        `archive=@${packagePath}`,
        "--form",
        "passwd=",
        `http://${rokuIp}/plugin_install`,
      ],
      { stdio: ["pipe", "inherit", "inherit"] },
    );
    curl.on("error", (error) =>
      reject(new Error(`Unable to run curl. Install curl and try again. (${error.message})`)),
    );
    curl.on("close", resolve);
    curl.stdin.end(`user = ${curlConfigString(`rokudev:${password}`)}\n`);
  });

  if (exitCode !== 0) {
    if (exitCode === 7 && process.platform === "darwin") {
      throw new Error(
        `Could not connect to the Roku at ${rokuIp}. If the Roku's developer page opens in your browser, macOS is blocking this terminal app: enable it under System Settings > Privacy & Security > Local Network, then quit and reopen it. You can also upload ${packagePath} through the developer page.`,
      );
    }
    if (exitCode === 22) {
      throw new Error(
        "Roku sideload was rejected. Confirm the Roku developer username is rokudev and re-enter the case-sensitive developer password shown/created in developer mode.",
      );
    }
    throw new Error("Roku sideload failed. Review the Roku installer response printed above.");
  }

  console.log(`Flight Lane was installed on ${rokuIp}.`);
});
