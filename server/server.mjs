import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(MODULE_DIR, "..");
const DEFAULT_ENV_PATH = path.join(REPO_ROOT, ".env.local");
const DEFAULT_AIRCRAFT_API = "https://api.adsb.lol/v2";
const BACKUP_AIRCRAFT_PROVIDERS = [
  {
    name: "adsb.lol",
    baseUrl: "https://api.adsb.lol/v2",
    pathStyle: "positional",
  },
  {
    name: "adsb.fi",
    baseUrl: "https://opendata.adsb.fi/api/v3",
    pathStyle: "named",
  },
  {
    name: "airplanes.live",
    baseUrl: "https://api.airplanes.live/v2",
    pathStyle: "positional",
  },
];
const FLIGHT_ROUTE_API = "https://api.adsbdb.com/v0/callsign";
const GEOCODING_API = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress";
// Public-domain USDA/USGS orthoimagery from The National Map (United States coverage).
const IMAGERY_EXPORT_API =
  "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/export";
const IMAGERY_ATTRIBUTION = "USDA, USGS The National Map";
const WEB_MERCATOR_RADIUS_METERS = 6378137;
const AIRCRAFT_PHOTO_API = "https://api.planespotters.net/pub/photos/reg";
const USER_AGENT = "FlightLaneSelfHosted/1.0";
const MAX_JSON_BYTES = 2 * 1024 * 1024;
const MAX_MAP_BYTES = 8 * 1024 * 1024;
const MAP_CACHE_MAX_ENTRIES = 200;
const MAX_REQUEST_BYTES = 16 * 1024;
const CALLSIGN_PATTERN = /^[A-Z0-9][A-Z0-9_-]{1,15}$/;
const REGISTRATION_PATTERN = /^[A-Z0-9][A-Z0-9-]{1,15}$/;

class TtlCache {
  constructor({ maxEntries = Infinity } = {}) {
    this.values = new Map();
    this.pending = new Map();
    this.maxEntries = maxEntries;
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
    this.values.delete(key);
    this.values.set(key, {
      expiresAt: Date.now() + Math.max(0, ttlSeconds) * 1000,
      value,
    });
    while (this.values.size > this.maxEntries) {
      this.values.delete(this.values.keys().next().value);
    }
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
    aircraftProviders: createAircraftProviders(aircraftBaseUrl),
    aircraftCacheSeconds: numberSetting(
      environment,
      "AIRCRAFT_CACHE_SECONDS",
      15,
      1,
      3600,
    ),
    mapCacheSeconds: numberSetting(environment, "MAP_CACHE_SECONDS", 86400, 0, 604800),
    flightRoutesEnabled: booleanSetting(environment, "ENABLE_FLIGHT_ROUTES", true),
    flightDetailsCacheSeconds: numberSetting(
      environment,
      "FLIGHT_DETAILS_CACHE_SECONDS",
      86400,
      60,
      604800,
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

function createAircraftProviders(configuredBaseUrl) {
  const providers = [
    aircraftProviderForBaseUrl(configuredBaseUrl),
    ...BACKUP_AIRCRAFT_PROVIDERS,
  ];
  const seen = new Set();
  return providers.filter((provider) => {
    const key = `${provider.pathStyle}:${provider.baseUrl.replace(/\/+$/, "")}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function aircraftProviderForBaseUrl(baseUrl) {
  const normalizedBaseUrl = String(baseUrl).replace(/\/+$/, "");
  const hostname = new URL(normalizedBaseUrl).hostname.toLowerCase();
  if (hostname.endsWith("adsb.fi")) {
    return { name: "adsb.fi", baseUrl: normalizedBaseUrl, pathStyle: "named" };
  }
  if (hostname.endsWith("adsb.lol")) {
    return { name: "adsb.lol", baseUrl: normalizedBaseUrl, pathStyle: "positional" };
  }
  if (hostname.endsWith("airplanes.live")) {
    return {
      name: "airplanes.live",
      baseUrl: normalizedBaseUrl,
      pathStyle: "positional",
    };
  }
  return { name: hostname || "configured", baseUrl: normalizedBaseUrl, pathStyle: "positional" };
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

function isAircraftPositionPayload(value) {
  return (
    value &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    (Array.isArray(value.ac) || Array.isArray(value.aircraft))
  );
}

function aircraftProviderUrl(provider, latitude, longitude, radiusNauticalMiles) {
  if (provider.pathStyle === "named") {
    return `${provider.baseUrl}/lat/${latitude}/lon/${longitude}/dist/${radiusNauticalMiles}`;
  }
  return `${provider.baseUrl}/point/${latitude}/${longitude}/${radiusNauticalMiles}`;
}

function logAircraftProviderFailure(provider, providerStatus, reason = "http_error") {
  console.error(
    JSON.stringify({
      event: "provider_error",
      feature: "Aircraft data",
      provider,
      providerStatus,
      reason,
    }),
  );
}

export async function fetchAircraftPositionsFromProviders({
  fetchImpl = globalThis.fetch,
  providers,
  latitude,
  longitude,
  radiusNauticalMiles,
  timeoutMs,
}) {
  const failures = [];
  for (const provider of providers) {
    const providerUrl = aircraftProviderUrl(
      provider,
      latitude,
      longitude,
      radiusNauticalMiles,
    );
    try {
      const upstream = await fetchJson(fetchImpl, providerUrl, {
        headers: providerHeaders(),
        signal: requestSignal(timeoutMs),
      });
      if (!upstream.ok) {
        failures.push({ provider: provider.name, status: upstream.status });
        logAircraftProviderFailure(provider.name, upstream.status);
        continue;
      }
      if (!isAircraftPositionPayload(upstream.data)) {
        failures.push({ provider: provider.name, status: 502 });
        logAircraftProviderFailure(provider.name, 502, "invalid_payload");
        continue;
      }
      return { payload: upstream.data, provider: provider.name, failures };
    } catch (error) {
      failures.push({ provider: provider.name });
      console.error(
        JSON.stringify({
          event: "provider_request_failed",
          feature: "Aircraft data",
          provider: provider.name,
          message: cleanText(error?.message, 180) || "Unknown error",
        }),
      );
    }
  }
  return { failures };
}

// Converts a center/zoom/size request (Web Mercator zoom levels) into a Web Mercator bounding box so the
// image covers exactly the area the Roku expects (scale 2: two image pixels per logical pixel).
export function mapBoundingBox(latitude, longitude, zoom, logicalSize) {
  const radians = Math.PI / 180;
  const centerX = WEB_MERCATOR_RADIUS_METERS * longitude * radians;
  const centerY =
    WEB_MERCATOR_RADIUS_METERS * Math.log(Math.tan(Math.PI / 4 + (latitude * radians) / 2));
  const metersPerLogicalPixel = (2 * Math.PI * WEB_MERCATOR_RADIUS_METERS) / 256 / 2 ** zoom;
  const half = (logicalSize * metersPerLogicalPixel) / 2;
  return [centerX - half, centerY - half, centerX + half, centerY + half].map((value) =>
    rounded(value, 2),
  );
}

const PROVIDER_DISPLAY_NAMES = {
  "airplanes.live": "Airplanes.live",
  "adsb.lol": "ADSB.lol",
  "adsb.fi": "ADSB.fi",
};

function providerDisplayName(provider) {
  return PROVIDER_DISPLAY_NAMES[provider] || cleanText(provider, 60);
}

// Returns an adsbdb route in the flight-list shape the Roku app parses.
function normalizeFlightRoute(callsign, data) {
  const route = data?.response?.flightroute;
  if (!route || typeof route !== "object") return { flights: [], source: "adsbdb.com" };
  const airport = (value) => ({
    code_iata: cleanText(value?.iata_code, 8),
    code_icao: cleanText(value?.icao_code, 8),
    name: cleanText(value?.name, 120),
    city: cleanText(value?.municipality, 80),
  });
  return {
    flights: [
      {
        ident: cleanText(route.callsign_icao, 16) || callsign,
        ident_iata: cleanText(route.callsign_iata, 16),
        operator: cleanText(route.airline?.name, 80),
        origin: airport(route.origin),
        destination: airport(route.destination),
      },
    ],
    source: "adsbdb.com",
  };
}

// Returns a Census match in the { status, results[].geometry.location } shape the Roku app parses.
async function geocodeWithCensus(fetchImpl, config, address) {
  const providerUrl = new URL(GEOCODING_API);
  providerUrl.searchParams.set("address", address);
  providerUrl.searchParams.set("benchmark", "Public_AR_Current");
  providerUrl.searchParams.set("format", "json");
  const upstream = await fetchJson(fetchImpl, providerUrl, {
    headers: providerHeaders(),
    signal: requestSignal(config.timeoutMs),
  });
  if (!upstream.ok) {
    const error = new Error("Address lookup request failed.");
    error.providerStatus = upstream.status;
    error.feature = "Address lookup";
    throw error;
  }
  const match = upstream.data?.result?.addressMatches?.[0];
  const latitude = Number(match?.coordinates?.y);
  const longitude = Number(match?.coordinates?.x);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return { status: "ZERO_RESULTS", results: [] };
  }
  return {
    status: "OK",
    results: [
      {
        formatted_address: cleanText(match.matchedAddress, 200) || address,
        geometry: { location: { lat: latitude, lng: longitude } },
      },
    ],
  };
}

export function createFlightLaneServer({
  config,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (!config) throw new Error("A server configuration is required.");
  const nearbyCache = new TtlCache();
  const detailsCache = new TtlCache();
  const geocodeCache = new TtlCache();
  const mapCache = new TtlCache({ maxEntries: MAP_CACHE_MAX_ENTRIES });
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
            satelliteMaps: true,
            addressLookup: true,
            flightDetails: config.flightRoutesEnabled,
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
            const result = await fetchAircraftPositionsFromProviders({
              fetchImpl,
              providers: config.aircraftProviders,
              latitude: roundedLatitude,
              longitude: roundedLongitude,
              radiusNauticalMiles: rounded(radiusNauticalMiles, 3),
              timeoutMs: config.timeoutMs,
            });
            if (result.payload === undefined || !result.provider) {
              const lastFailure = result.failures[result.failures.length - 1];
              const error = new Error("Aircraft data request failed.");
              error.providerStatus = lastFailure?.status || 502;
              throw error;
            }
            if (result.failures.length > 0) {
              console.warn(
                JSON.stringify({
                  event: "provider_fallback",
                  feature: "Aircraft data",
                  provider: result.provider,
                  failedProviders: result.failures.map((failure) => failure.provider),
                }),
              );
            }
            return { payload: result.payload, provider: result.provider };
          },
        );
        const payload = {
          ...cached.value.payload,
          flightLaneSource: providerDisplayName(cached.value.provider),
        };
        writeJson(response, 200, payload, {
          "X-FlightLane-Cache": cached.cacheStatus,
          "X-FlightLane-Provider": cached.value.provider,
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
        if (!config.flightRoutesEnabled) {
          writeJson(response, 200, { flights: [] });
          return;
        }
        const cached = await detailsCache.getOrLoad(
          callsign,
          config.flightDetailsCacheSeconds,
          async () => {
            const providerUrl = `${FLIGHT_ROUTE_API}/${encodeURIComponent(callsign)}`;
            const upstream = await fetchJson(fetchImpl, providerUrl, {
              headers: providerHeaders(),
              signal: requestSignal(config.timeoutMs),
            });
            if (upstream.status === 404) return { flights: [] };
            if (!upstream.ok) {
              const error = new Error("Flight route request failed.");
              error.providerStatus = upstream.status;
              error.feature = "Flight route";
              throw error;
            }
            return normalizeFlightRoute(callsign, upstream.data);
          },
        );
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      if (method === "POST" && url.pathname === "/v1/geocode") {
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
          return geocodeWithCensus(fetchImpl, config, address);
        });
        writeJson(response, 200, cached.value, {
          "X-FlightLane-Cache": cached.cacheStatus,
        });
        return;
      }

      if (method === "GET" && url.pathname === "/v1/map") {
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

        const bbox = mapBoundingBox(rounded(latitude, 5), rounded(longitude, 5), zoom, logicalSize);
        const cached = await mapCache.getOrLoad(
          `${bbox.join(",")}|${logicalSize}`,
          config.mapCacheSeconds,
          async () => {
            const imageSize = logicalSize * 2;
            const providerUrl = new URL(IMAGERY_EXPORT_API);
            providerUrl.searchParams.set("bbox", bbox.join(","));
            providerUrl.searchParams.set("bboxSR", "3857");
            providerUrl.searchParams.set("imageSR", "3857");
            providerUrl.searchParams.set("size", `${imageSize},${imageSize}`);
            providerUrl.searchParams.set("format", "jpg");
            providerUrl.searchParams.set("f", "image");

            const upstream = await fetchImpl(providerUrl, {
              headers: { "User-Agent": USER_AGENT },
              signal: requestSignal(config.timeoutMs),
            });
            const contentType = upstream.headers.get("content-type") || "";
            if (!upstream.ok || !contentType.startsWith("image/")) {
              const error = new Error("Satellite map request failed.");
              error.providerStatus = upstream.status;
              error.feature = "Satellite map";
              throw error;
            }
            return {
              contentType,
              image: await readResponseBytes(upstream, MAX_MAP_BYTES),
            };
          },
        );
        response.writeHead(
          200,
          secureHeaders({
            "Content-Type": cached.value.contentType,
            "Content-Length": String(cached.value.image.length),
            "X-FlightLane-Cache": cached.cacheStatus,
            "X-FlightLane-Attribution": IMAGERY_ATTRIBUTION,
          }),
        );
        response.end(cached.value.image);
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
        writeProviderError(response, error.feature || "Provider data", error.providerStatus);
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
    `Features: maps=usgs geocoding=census flightRoutes=${config.flightRoutesEnabled} photos=${
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
