import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(MODULE_DIR, "..");
const DEFAULT_ENV_PATH = path.join(REPO_ROOT, ".env.local");
const DEFAULT_AIRCRAFT_API = "https://api.airplanes.live/v2";
const FLIGHT_DETAILS_API = "https://aeroapi.flightaware.com/aeroapi";
const GEOCODING_API = "https://maps.googleapis.com/maps/api/geocode/json";
const STATIC_MAP_API = "https://maps.googleapis.com/maps/api/staticmap";
const AIRCRAFT_PHOTO_API = "https://api.planespotters.net/pub/photos/reg";
const USER_AGENT = "FlightLaneSelfHosted/1.0";
const MAX_JSON_BYTES = 2 * 1024 * 1024;
const MAX_MAP_BYTES = 8 * 1024 * 1024;
const MAX_REQUEST_BYTES = 16 * 1024;
const CALLSIGN_PATTERN = /^[A-Z0-9][A-Z0-9_-]{1,15}$/;
const REGISTRATION_PATTERN = /^[A-Z0-9][A-Z0-9-]{1,15}$/;

class TtlCache {
  constructor() {
    this.values = new Map();
    this.pending = new Map();
  }

  get(key) {
    const record = this.values.get(key);
    if (!record) return undefined;
    if (record.expiresAt <= Date.now()) {
      this.values.delete(key);
      return undefined;
    }
    return record.value;
  }

  set(key, value, ttlSeconds) {
    this.values.set(key, {
      expiresAt: Date.now() + Math.max(0, ttlSeconds) * 1000,
      value,
    });
  }

  async getOrLoad(key, ttlSeconds, loader) {
    const cached = this.get(key);
    if (cached !== undefined) return { cacheStatus: "hit", value: cached };

    let pending = this.pending.get(key);
    if (!pending) {
      pending = loader();
      this.pending.set(key, pending);
    }

    try {
      const value = await pending;
      this.set(key, value, ttlSeconds);
      return { cacheStatus: "miss", value };
    } finally {
      this.pending.delete(key);
    }
  }
}

export function parseEnv(text) {
  const values = {};
  for (const rawLine of String(text).split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const name = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values[name] = value;
  }
  return values;
}

export function loadEnvironment(envPath = DEFAULT_ENV_PATH) {
  if (!fs.existsSync(envPath)) {
    throw new Error(
      `Missing ${path.basename(envPath)}. Copy .env.example to .env.local and fill in your settings.`,
    );
  }
  return { ...parseEnv(fs.readFileSync(envPath, "utf8")), ...process.env };
}

function numberSetting(environment, name, fallback, minimum, maximum) {
  const raw = environment[name];
  const value = raw === undefined || raw === "" ? fallback : Number(raw);
  if (!Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be a number from ${minimum} to ${maximum}.`);
  }
  return value;
}

function booleanSetting(environment, name, fallback) {
  const raw = environment[name];
  if (raw === undefined || raw === "") return fallback;
  if (/^(1|true|yes|on)$/i.test(raw)) return true;
  if (/^(0|false|no|off)$/i.test(raw)) return false;
  throw new Error(`${name} must be true or false.`);
}

export function createConfig(environment) {
  const mapsKey = String(environment.GOOGLE_MAPS_API_KEY || "").trim();
  const geocodingKey = String(environment.GOOGLE_GEOCODING_API_KEY || mapsKey).trim();
  const aircraftBaseUrl = String(
    environment.AIRCRAFT_API_BASE_URL || DEFAULT_AIRCRAFT_API,
  ).replace(/\/+$/, "");
  const parsedAircraftUrl = new URL(aircraftBaseUrl);
  if (!["http:", "https:"].includes(parsedAircraftUrl.protocol)) {
    throw new Error("AIRCRAFT_API_BASE_URL must use HTTP or HTTPS.");
  }

  return {
    host: String(environment.LOCAL_API_HOST || "0.0.0.0").trim(),
    port: numberSetting(environment, "LOCAL_API_PORT", 8787, 1, 65535),
    localNetworkOnly: booleanSetting(environment, "LOCAL_NETWORK_ONLY", true),
    timeoutMs: numberSetting(environment, "PROVIDER_TIMEOUT_MS", 10000, 1000, 60000),
    aircraftBaseUrl,
    aircraftCacheSeconds: numberSetting(
      environment,
      "AIRCRAFT_CACHE_SECONDS",
      15,
      1,
      3600,
    ),
    mapsKey,
    geocodingKey,
    flightAwareKey: String(environment.FLIGHTAWARE_API_KEY || "").trim(),
    flightDetailsCacheSeconds: numberSetting(
      environment,
      "FLIGHT_DETAILS_CACHE_SECONDS",
      900,
      60,
      86400,
    ),
    aircraftPhotosEnabled: booleanSetting(
      environment,
      "ENABLE_AIRCRAFT_PHOTOS",
      true,
    ),
    aircraftPhotoCacheSeconds: numberSetting(
      environment,
      "AIRCRAFT_PHOTO_CACHE_SECONDS",
      3600,
      300,
      86400,
    ),
  };
}

export function isPrivateNetworkAddress(rawAddress) {
  if (!rawAddress) return false;
  let address = String(rawAddress).toLowerCase();
  if (address.startsWith("::ffff:")) address = address.slice(7);
  if (address === "::1") return true;
  if (address.startsWith("fe80:") || address.startsWith("fc") || address.startsWith("fd")) {
    return true;
  }
  const octets = address.split(".").map(Number);
  if (octets.length !== 4 || octets.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return false;
  }
  return (
    octets[0] === 10 ||
    octets[0] === 127 ||
    (octets[0] === 169 && octets[1] === 254) ||
    (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
    (octets[0] === 192 && octets[1] === 168)
  );
}

function cleanText(value, maximumLength) {
  if (typeof value !== "string") return undefined;
  const cleaned = value.replace(/[\u0000-\u001F\u007F]/g, "").trim();
  return cleaned ? cleaned.slice(0, maximumLength) : undefined;
}

function safeHttpsUrl(value, allowedHosts) {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || !allowedHosts.includes(url.hostname)) return undefined;
    return url.toString();
  } catch {
    return undefined;
  }
}

function positiveNumber(value) {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : undefined;
}

export function normalizeProviderPayload(registration, payload) {
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.photos)) {
    return { available: false, registration };
  }

  for (const candidate of payload.photos) {
    if (!candidate || typeof candidate !== "object" || !candidate.thumbnail) continue;
    const imageUrl = safeHttpsUrl(candidate.thumbnail.src, ["t.plnspttrs.net"]);
    const sourceUrl = safeHttpsUrl(candidate.link, [
      "planespotters.net",
      "www.planespotters.net",
    ]);
    if (!imageUrl || !sourceUrl) continue;

    const photographer = cleanText(candidate.photographer, 80);
    const size =
      candidate.thumbnail.size && typeof candidate.thumbnail.size === "object"
        ? candidate.thumbnail.size
        : {};
    return {
      available: true,
      registration,
      imageUrl,
      sourceUrl,
      photographer,
      attribution: photographer
        ? `(c) ${photographer} / Planespotters.net`
        : "(c) Planespotters.net",
      width: positiveNumber(size.width),
      height: positiveNumber(size.height),
    };
  }
  return { available: false, registration };
}

function secureHeaders(extra = {}) {
  return {
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    ...extra,
  };
}

function writeJson(response, status, body, extraHeaders = {}) {
  const encoded = Buffer.from(JSON.stringify(body));
  response.writeHead(
    status,
    secureHeaders({
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": String(encoded.length),
      ...extraHeaders,
    }),
  );
  response.end(encoded);
}

function writeProviderError(response, feature, providerStatus) {
  console.error(
    JSON.stringify({ event: "provider_error", feature, providerStatus }),
  );
  writeJson(response, 502, {
    ok: false,
    error: `${feature} is temporarily unavailable.`,
  });
}

async function readRequestJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) throw new Error("Request body is too large.");
    chunks.push(chunk);
  }
  if (size === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function readResponseBytes(response, maximumBytes) {
  const declaredLength = Number(response.headers.get("content-length") || "0");
  if (declaredLength > maximumBytes) throw new Error("Provider response is too large.");
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length > maximumBytes) throw new Error("Provider response is too large.");
  return buffer;
}

async function fetchJson(fetchImpl, url, options, maximumBytes = MAX_JSON_BYTES) {
  const upstream = await fetchImpl(url, options);
  if (!upstream.ok) return { ok: false, status: upstream.status };
  const body = await readResponseBytes(upstream, maximumBytes);
  return { ok: true, status: upstream.status, data: JSON.parse(body.toString("utf8")) };
}

function queryNumber(url, name) {
  const raw = url.searchParams.get(name);
  if (raw === null || raw.trim() === "") return undefined;
  const value = Number(raw);
  return Number.isFinite(value) ? value : undefined;
}

function rounded(value, decimals) {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function providerHeaders(extra = {}) {
  return {
    Accept: "application/json",
    "User-Agent": USER_AGENT,
    ...extra,
  };
}

function requestSignal(timeoutMs) {
  return AbortSignal.timeout(timeoutMs);
}

export function createFlightLaneServer({
  config,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (!config) throw new Error("A server configuration is required.");
  const nearbyCache = new TtlCache();
  const detailsCache = new TtlCache();
  const geocodeCache = new TtlCache();
  const photoCache = new TtlCache();
  const startedAt = Date.now();

  return http.createServer(async (request, response) => {
    try {
      if (
        config.localNetworkOnly &&
        !isPrivateNetworkAddress(request.socket.remoteAddress)
      ) {
        writeJson(response, 403, {
          ok: false,
          error: "This service accepts private-network requests only.",
        });
        return;
      }

      const url = new URL(request.url || "/", "http://flightlane.local");
      const method = request.method || "GET";

      if (method === "GET" && url.pathname === "/health") {
        writeJson(response, 200, {
          ok: true,
          service: "Flight Lane local service",
          uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
          features: {
            liveAircraft: true,
            satelliteMaps: Boolean(config.mapsKey),
            addressLookup: Boolean(config.geocodingKey),
            flightDetails: Boolean(config.flightAwareKey),
            aircraftPhotos: config.aircraftPhotosEnabled,
          },
        });
        return;
      }

      if (method === "POST" && url.pathname === "/v1/register") {
        await readRequestJson(request);
        writeJson(response, 200, {
          ok: true,
          token: "local-session",
          expiresAt: "",
        });
        return;
      }

      if (method === "GET" && url.pathname === "/v1/aircraft/nearby") {
        const latitude = queryNumber(url, "latitude");
        const longitude = queryNumber(url, "longitude");
        const radiusMiles = queryNumber(url, "radiusMiles");
        if (
          latitude === undefined ||
          longitude === undefined ||
          radiusMiles === undefined ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          radiusMiles < 1 ||
          radiusMiles > 10
        ) {
          writeJson(response, 400, {
            ok: false,
            error: "Valid coordinates and a radius from 1 to 10 miles are required.",
          });
          return;
        }

        const roundedLatitude = rounded(latitude, 4);
        const roundedLongitude = rounded(longitude, 4);
        const roundedRadius = rounded(radiusMiles, 2);
        const cacheKey = `${roundedLatitude}/${roundedLongitude}/${roundedRadius}`;
        const cached = await nearbyCache.getOrLoad(
          cacheKey,
          config.aircraftCacheSeconds,
          async () => {
            const radiusNauticalMiles = roundedRadius / 1.150779;
            const providerUrl =
              `${config.aircraftBaseUrl}/point/${roundedLatitude}/` +
              `${roundedLongitude}/${rounded(radiusNauticalMiles, 3)}`;
            const upstream = await fetchJson(fetchImpl, providerUrl, {
              headers: providerHeaders(),
              signal: requestSignal(config.timeoutMs),
            });
            if (!upstream.ok) {
              const error = new Error("Aircraft data request failed.");
              error.providerStatus = upstream.status;
              throw error;
            }
            return upstream.data;
          },
        );
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      const flightMatch = url.pathname.match(/^\/v1\/flights\/([^/]+)$/);
      if (method === "GET" && flightMatch) {
        const callsign = decodeURIComponent(flightMatch[1]).trim().toUpperCase();
        if (!CALLSIGN_PATTERN.test(callsign)) {
          writeJson(response, 400, { ok: false, error: "Invalid flight number." });
          return;
        }
        if (!config.flightAwareKey) {
          writeJson(response, 200, { flights: [] });
          return;
        }
        const cached = await detailsCache.getOrLoad(
          callsign,
          config.flightDetailsCacheSeconds,
          async () => {
            const providerUrl =
              `${FLIGHT_DETAILS_API}/flights/${encodeURIComponent(callsign)}` +
              "?max_pages=1";
            const upstream = await fetchJson(fetchImpl, providerUrl, {
              headers: providerHeaders({ "x-apikey": config.flightAwareKey }),
              signal: requestSignal(config.timeoutMs),
            });
            if (!upstream.ok) {
              const error = new Error("Flight details request failed.");
              error.providerStatus = upstream.status;
              throw error;
            }
            return upstream.data;
          },
        );
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      if (method === "POST" && url.pathname === "/v1/geocode") {
        if (!config.geocodingKey) {
          writeJson(response, 503, {
            ok: false,
            error:
              "Address lookup is not configured. Add a Google Geocoding API key to .env.local.",
          });
          return;
        }
        const payload = await readRequestJson(request);
        const address = cleanText(payload.address, 200);
        if (!address || address.length < 5) {
          writeJson(response, 400, {
            ok: false,
            error: "Enter a complete address.",
          });
          return;
        }
        const cacheKey = address.toLowerCase();
        const cached = await geocodeCache.getOrLoad(cacheKey, 86400, async () => {
          const providerUrl = new URL(GEOCODING_API);
          providerUrl.searchParams.set("address", address);
          providerUrl.searchParams.set("key", config.geocodingKey);
          const upstream = await fetchJson(fetchImpl, providerUrl, {
            headers: providerHeaders(),
            signal: requestSignal(config.timeoutMs),
          });
          if (!upstream.ok) {
            const error = new Error("Address lookup request failed.");
            error.providerStatus = upstream.status;
            throw error;
          }
          return upstream.data;
        });
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      if (method === "GET" && url.pathname === "/v1/map") {
        if (!config.mapsKey) {
          writeJson(response, 503, {
            ok: false,
            error:
              "Satellite maps are not configured. Add a Google Maps API key to .env.local.",
          });
          return;
        }
        const latitude = queryNumber(url, "latitude");
        const longitude = queryNumber(url, "longitude");
        const zoom = queryNumber(url, "zoom");
        const logicalSize = url.searchParams.has("size")
          ? queryNumber(url, "size")
          : 640;
        if (
          latitude === undefined ||
          longitude === undefined ||
          zoom === undefined ||
          logicalSize === undefined ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          !Number.isInteger(zoom) ||
          zoom < 0 ||
          zoom > 21 ||
          !Number.isInteger(logicalSize) ||
          logicalSize < 128 ||
          logicalSize > 640
        ) {
          writeJson(response, 400, { ok: false, error: "Invalid map request." });
          return;
        }

        const providerUrl = new URL(STATIC_MAP_API);
        providerUrl.searchParams.set(
          "center",
          `${rounded(latitude, 5)},${rounded(longitude, 5)}`,
        );
        providerUrl.searchParams.set("zoom", String(zoom));
        providerUrl.searchParams.set("size", `${logicalSize}x${logicalSize}`);
        providerUrl.searchParams.set("scale", "2");
        providerUrl.searchParams.set("maptype", "hybrid");
        providerUrl.searchParams.set("format", "jpg-baseline");
        providerUrl.searchParams.set("language", "en");
        providerUrl.searchParams.set("region", "US");
        providerUrl.searchParams.set("key", config.mapsKey);

        const upstream = await fetchImpl(providerUrl, {
          headers: { "User-Agent": USER_AGENT },
          signal: requestSignal(config.timeoutMs),
        });
        const contentType = upstream.headers.get("content-type") || "";
        if (!upstream.ok || !contentType.startsWith("image/")) {
          writeProviderError(response, "Satellite map", upstream.status);
          return;
        }
        const image = await readResponseBytes(upstream, MAX_MAP_BYTES);
        response.writeHead(
          200,
          secureHeaders({
            "Content-Type": contentType,
            "Content-Length": String(image.length),
          }),
        );
        response.end(image);
        return;
      }

      const photoMatch = url.pathname.match(/^\/v1\/aircraft-photo\/([^/]+)$/);
      if (method === "GET" && photoMatch) {
        const registration = decodeURIComponent(photoMatch[1]).trim().toUpperCase();
        if (!REGISTRATION_PATTERN.test(registration)) {
          writeJson(response, 400, {
            ok: false,
            error: "Invalid aircraft registration.",
          });
          return;
        }
        if (!config.aircraftPhotosEnabled) {
          writeJson(response, 200, {
            ok: true,
            available: false,
            registration,
          });
          return;
        }
        const cached = await photoCache.getOrLoad(
          registration,
          config.aircraftPhotoCacheSeconds,
          async () => {
            const providerUrl =
              `${AIRCRAFT_PHOTO_API}/${encodeURIComponent(registration)}`;
            const upstream = await fetchJson(fetchImpl, providerUrl, {
              headers: providerHeaders(),
              signal: requestSignal(config.timeoutMs),
            });
            if (!upstream.ok) {
              const error = new Error("Aircraft photo request failed.");
              error.providerStatus = upstream.status;
              throw error;
            }
            return { ok: true, ...normalizeProviderPayload(registration, upstream.data) };
          },
        );
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      writeJson(response, 404, { ok: false, error: "Not found." });
    } catch (error) {
      if (error && Number.isInteger(error.providerStatus)) {
        writeProviderError(response, "Provider data", error.providerStatus);
        return;
      }
      const isInputError =
        error instanceof SyntaxError ||
        /Request body|complete address/i.test(String(error?.message));
      console.error(
        JSON.stringify({
          event: isInputError ? "request_error" : "server_error",
          message: cleanText(error?.message, 180) || "Unknown error",
        }),
      );
      writeJson(response, isInputError ? 400 : 502, {
        ok: false,
        error: isInputError
          ? "The request was invalid."
          : "The requested data is temporarily unavailable.",
      });
    }
  });
}

export async function startServer({
  environment = loadEnvironment(process.env.FLIGHTLANE_ENV_FILE || DEFAULT_ENV_PATH),
  fetchImpl = globalThis.fetch,
} = {}) {
  const config = createConfig(environment);
  const server = createFlightLaneServer({ config, fetchImpl });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(config.port, config.host, resolve);
  });
  console.log(`Flight Lane local service is listening on http://${config.host}:${config.port}`);
  console.log(
    `Features: maps=${Boolean(config.mapsKey)} geocoding=${Boolean(
      config.geocodingKey,
    )} flightDetails=${Boolean(config.flightAwareKey)} photos=${
      config.aircraftPhotosEnabled
    }`,
  );
  return server;
}

const isDirectRun =
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isDirectRun) {
  startServer().catch((error) => {
    console.error(`Flight Lane could not start: ${error.message}`);
    process.exitCode = 1;
  });
}
