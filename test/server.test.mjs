import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import {
  createConfig,
  createFlightLaneServer,
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
