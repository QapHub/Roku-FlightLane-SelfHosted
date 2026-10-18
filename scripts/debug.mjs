import net from "node:net";
import { parseArgs, readEnvFile, requireRokuIp, resolveEnvPath, runMain } from "./lib/common.mjs";

function protectDebugLine(line) {
  return line
    .replace(/([?&](?:key|x-apikey|address|center|latitude|longitude)=)[^&\s]+/gi, "$1[redacted]")
    .replace(/(Authorization\s*[:=]\s*Bearer\s+)[A-Za-z0-9._-]+/gi, "$1[redacted]");
}

runMain(async () => {
  const options = parseArgs();
  const environmentFile = options["env-file"] || ".env.local";
  const durationSeconds = Number.parseInt(options.duration ?? "0", 10) || 0;
  const rokuIp = requireRokuIp(
    readEnvFile(resolveEnvPath(environmentFile), `Missing ${environmentFile}.`),
    environmentFile,
  );

  await new Promise((resolve, reject) => {
    const socket = net.connect(8085, rokuIp);
    let buffered = "";
    let discardFirstLine = true;

    socket.setEncoding("utf8");
    socket.on("connect", () => {
      console.log(`Connected to the Roku BrightScript console at ${rokuIp}:8085. Press Ctrl+C to stop.`);
      if (durationSeconds > 0) {
        setTimeout(() => socket.end(), durationSeconds * 1000).unref();
      }
    });
    socket.on("data", (chunk) => {
      buffered += chunk;
      const lines = buffered.split(/\r?\n/);
      buffered = lines.pop();
      for (const line of lines) {
        if (discardFirstLine) {
          discardFirstLine = false;
          continue;
        }
        console.log(protectDebugLine(line));
      }
    });
    socket.on("error", reject);
    socket.on("close", resolve);
  });
});
