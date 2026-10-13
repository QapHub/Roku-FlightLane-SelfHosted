import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import {
  createConfig,
  createFlightLaneServer,
  fetchAircraftPositionsFromProviders,
  isPrivateNetworkAddress,
  normalizeProviderPayload,
  parseEnv,
} from "../server/server.mjs";

function testConfig(overrides = {}) {
  return createConfig({
    LOCAL_API_PORT: "8787",
    LOCAL_NETWORK_ONLY: "true",
    ...overrides,
  });
}

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}`;
}

test("parseEnv handles comments, whitespace, and quoted values", () => {
  assert.deepEqual(
    parseEnv('# comment\nONE=first\nTWO = "two words"\nTHREE=\'3\'\n'),
    { ONE: "first", TWO: "two words", THREE: "3" },
  );
});

test("private network detection accepts LAN addresses and rejects public addresses", () => {
  for (const address of [
    "127.0.0.1",
    "::1",
    "::ffff:192.168.1.25",
    "10.2.3.4",
    "172.31.4.5",
    "fd00::10",
  ]) {
    assert.equal(isPrivateNetworkAddress(address), true, address);
  }
  for (const address of ["8.8.8.8", "172.32.0.1", "203.0.113.8"]) {
    assert.equal(isPrivateNetworkAddress(address), false, address);
  }
});

test("createConfig keeps optional provider keys disabled when blank", () => {
  const config = testConfig();
  assert.equal(config.mapsKey, "");
  assert.equal(config.geocodingKey, "");
  assert.equal(config.flightAwareKey, "");
  assert.equal(config.localNetworkOnly, true);
  assert.deepEqual(
    config.aircraftProviders.map((provider) => provider.name),
    ["airplanes.live", "adsb.lol", "adsb.fi"],
  );
});

test("photo payload normalization allows only expected HTTPS hosts", () => {
  const available = normalizeProviderPayload("N123AB", {
    photos: [
      {
        thumbnail: {
          src: "https://t.plnspttrs.net/12345.jpg",
          size: { width: 400, height: 225 },
        },
        link: "https://www.planespotters.net/photo/12345",
        photographer: "Aviation Photographer",
      },
    ],
  });
  assert.equal(available.available, true);
  assert.equal(available.registration, "N123AB");
  assert.equal(available.width, 400);

  const rejected = normalizeProviderPayload("N123AB", {
    photos: [
      {
        thumbnail: { src: "https://example.com/untrusted.jpg" },
        link: "https://www.planespotters.net/photo/12345",
      },
    ],
  });
  assert.deepEqual(rejected, { available: false, registration: "N123AB" });
});

test("health and local registration never expose provider keys", async (context) => {
  const secretValues = {
    GOOGLE_MAPS_API_KEY: "maps-test-secret",
    GOOGLE_GEOCODING_API_KEY: "geocode-test-secret",
    FLIGHTAWARE_API_KEY: "flight-test-secret",
  };
  const server = createFlightLaneServer({ config: testConfig(secretValues) });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const health = await fetch(`${baseUrl}/health`);
  assert.equal(health.status, 200);
  const healthText = await health.text();
  assert.doesNotMatch(healthText, /test-secret/);
  assert.equal(JSON.parse(healthText).features.flightDetails, true);

  const registration = await fetch(`${baseUrl}/v1/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ deviceId: "test-device" }),
  });
  assert.equal(registration.status, 200);
  assert.equal((await registration.json()).token, "local-session");
});

test("nearby requests are cached and convert statute miles to nautical miles", async (context) => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    return Response.json({ ac: [], now: 1234567890000 });
  };
  const server = createFlightLaneServer({
    config: testConfig({ AIRCRAFT_CACHE_SECONDS: "30" }),
    fetchImpl,
  });
  context.after(() => server.close());
  const baseUrl = await listen(server);
  const query = "/v1/aircraft/nearby?latitude=28.5&longitude=-81.6&radiusMiles=4";

  const first = await fetch(baseUrl + query);
  const second = await fetch(baseUrl + query);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(first.headers.get("x-flightlane-cache"), "miss");
  assert.equal(second.headers.get("x-flightlane-cache"), "hit");
  assert.equal(requestedUrls.length, 1);
  assert.match(requestedUrls[0], /\/point\/28\.5\/-81\.6\/3\.476$/);
});

test("nearby requests fall back when the configured aircraft provider fails", async () => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    if (requestedUrls.length === 1) {
      return new Response(JSON.stringify({ error: "blocked" }), { status: 403 });
    }
    return Response.json({ ac: [], now: 1234567890000 });
  };

  const result = await fetchAircraftPositionsFromProviders({
    fetchImpl,
    providers: testConfig().aircraftProviders,
    latitude: 28.5,
    longitude: -81.6,
    radiusNauticalMiles: 3.476,
    timeoutMs: 1000,
  });

  assert.equal(result.provider, "adsb.lol");
  assert.deepEqual(result.failures, [{ provider: "airplanes.live", status: 403 }]);
  assert.match(requestedUrls[0], /^https:\/\/api\.airplanes\.live\/v2\/point\/28\.5\/-81\.6\/3\.476$/);
  assert.match(requestedUrls[1], /^https:\/\/api\.adsb\.lol\/v2\/point\/28\.5\/-81\.6\/3\.476$/);
});

test("aircraft provider fallback supports ADSB.fi named path style", async () => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    if (requestedUrls.length < 3) {
      return new Response(JSON.stringify({ error: "busy" }), { status: 429 });
    }
    return Response.json({ ac: [], now: 1234567890000 });
  };

  const result = await fetchAircraftPositionsFromProviders({
    fetchImpl,
    providers: testConfig().aircraftProviders,
    latitude: 28.5,
    longitude: -81.6,
    radiusNauticalMiles: 3.476,
    timeoutMs: 1000,
  });

  assert.equal(result.provider, "adsb.fi");
  assert.deepEqual(result.failures, [
    { provider: "airplanes.live", status: 429 },
    { provider: "adsb.lol", status: 429 },
  ]);
  assert.equal(
    requestedUrls[2],
    "https://opendata.adsb.fi/api/v3/lat/28.5/lon/-81.6/dist/3.476",
  );
});

test("geocoding uses Census unless a dedicated Google key is configured", () => {
  assert.equal(testConfig().geocodingProvider, "census");
  assert.equal(testConfig({ GOOGLE_MAPS_API_KEY: "maps" }).geocodingProvider, "census");
  assert.equal(testConfig({ GOOGLE_GEOCODING_API_KEY: "geo" }).geocodingProvider, "google");
  const forcedGoogle = testConfig({ GEOCODING_PROVIDER: "google", GOOGLE_MAPS_API_KEY: "maps" });
  assert.equal(forcedGoogle.geocodingProvider, "google");
  assert.equal(forcedGoogle.geocodingKey, "maps");
  assert.throws(() => testConfig({ GEOCODING_PROVIDER: "other" }), /GEOCODING_PROVIDER/);
});

test("Census geocoding returns the Google response shape the Roku parses", async (context) => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    if (requestedUrls.length === 1) {
      return Response.json({
        result: {
          addressMatches: [
            {
              matchedAddress: "1 MAIN ST, ORLANDO, FL, 32801",
              coordinates: { x: -81.38, y: 28.54 },
            },
          ],
        },
      });
    }
    return Response.json({ result: { addressMatches: [] } });
  };
  const server = createFlightLaneServer({ config: testConfig(), fetchImpl });
  context.after(() => server.close());
  const baseUrl = await listen(server);
  const geocode = (address) =>
    fetch(`${baseUrl}/v1/geocode`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ address }),
    }).then((response) => response.json());

  assert.deepEqual(await geocode("1 Main St, Orlando, FL 32801"), {
    status: "OK",
    results: [
      {
        formatted_address: "1 MAIN ST, ORLANDO, FL, 32801",
        geometry: { location: { lat: 28.54, lng: -81.38 } },
      },
    ],
  });
  assert.match(requestedUrls[0], /^https:\/\/geocoding\.geo\.census\.gov\//);
  assert.doesNotMatch(requestedUrls[0], /key=/);
  assert.deepEqual(await geocode("99 Nowhere Rd, Nowhere"), { status: "ZERO_RESULTS", results: [] });
});

test("satellite maps are cached and honor provider cache limits", async (context) => {
  let cacheControl = "public, max-age=86400";
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    return new Response(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), {
      headers: { "Content-Type": "image/jpeg", "Cache-Control": cacheControl },
    });
  };
  const server = createFlightLaneServer({
    config: testConfig({ GOOGLE_MAPS_API_KEY: "maps-test-secret" }),
    fetchImpl,
  });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const cached = "/v1/map?latitude=28.5&longitude=-81.6&zoom=15";
  const [first, second] = await Promise.all([fetch(baseUrl + cached), fetch(baseUrl + cached)]);
  const third = await fetch(baseUrl + cached);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(third.headers.get("x-flightlane-cache"), "hit");
  assert.deepEqual([...new Uint8Array(await third.arrayBuffer())], [0xff, 0xd8, 0xff, 0xd9]);
  assert.equal(requestedUrls.length, 1);

  cacheControl = "no-store";
  const uncached = "/v1/map?latitude=28.6&longitude=-81.6&zoom=15";
  await (await fetch(baseUrl + uncached)).arrayBuffer();
  await (await fetch(baseUrl + uncached)).arrayBuffer();
  assert.equal(requestedUrls.length, 3);
});
