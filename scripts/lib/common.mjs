import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parseEnv } from "../../server/server.mjs";

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

export function parseArgs(argv = process.argv.slice(2)) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) continue;
    const [name, inlineValue] = argument.slice(2).split("=", 2);
    if (inlineValue !== undefined) {
      options[name] = inlineValue;
    } else if (index + 1 < argv.length && !argv[index + 1].startsWith("--")) {
      options[name] = argv[index + 1];
      index += 1;
    } else {
      options[name] = true;
    }
  }
  return options;
}

export function resolveEnvPath(environmentFile = ".env.local") {
  return path.resolve(REPO_ROOT, environmentFile);
}

export function readEnvFile(envPath, missingMessage) {
  if (!fs.existsSync(envPath)) {
    throw new Error(missingMessage || `Missing ${path.basename(envPath)}.`);
  }
  return parseEnv(fs.readFileSync(envPath, "utf8"));
}

export function requireRokuIp(config, environmentFile) {
  const rokuIp = String(config.ROKU_DEVICE_IP || "").trim();
  if (!rokuIp) {
    throw new Error(`ROKU_DEVICE_IP is missing from ${environmentFile}.`);
  }
  return rokuIp;
}

// Reads a line without echoing it, for secrets such as the Roku developer password.
export function promptHidden(question) {
  const input = process.stdin;
  const output = process.stdout;
  output.write(question);

  if (!input.isTTY) {
    return new Promise((resolve, reject) => {
      let buffer = "";
      const onData = (chunk) => {
        buffer += chunk;
        const newline = buffer.search(/\r?\n/);
        if (newline >= 0) {
          cleanup();
          output.write("\n");
          resolve(buffer.slice(0, newline));
        }
      };
      const onEnd = () => {
        cleanup();
        output.write("\n");
        resolve(buffer);
      };
      const onError = (error) => {
        cleanup();
        reject(error);
      };
      const cleanup = () => {
        input.off("data", onData);
        input.off("end", onEnd);
        input.off("error", onError);
        input.pause();
      };
      input.setEncoding("utf8");
      input.on("data", onData);
      input.on("end", onEnd);
      input.on("error", onError);
      input.resume();
    });
  }

  return new Promise((resolve, reject) => {
    let value = "";
    const onData = (chunk) => {
      // Terminals may wrap pasted text in bracketed-paste markers; they are not part of it.
      chunk = String(chunk).replace(/\u001b\[20[01]~/g, "");
      for (const character of chunk) {
        if (character === "\r" || character === "\n" || character === "\u0004") {
          cleanup();
          output.write("\n");
          resolve(value);
          return;
        }
        if (character === "\u0003") {
          cleanup();
          output.write("\n");
          reject(new Error("Cancelled."));
          return;
        }
        if (character === "\u007f" || character === "\b") {
          value = value.slice(0, -1);
        } else {
          value += character;
        }
      }
    };
    const cleanup = () => {
      input.off("data", onData);
      input.setRawMode(false);
      input.pause();
    };
    input.setEncoding("utf8");
    input.setRawMode(true);
    input.on("data", onData);
    input.resume();
  });
}

export function runMain(main) {
  Promise.resolve()
    .then(main)
    .catch((error) => {
      console.error(error instanceof Error ? error.message : error);
      process.exitCode = 1;
    });
}
