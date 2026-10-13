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

test("createConfig defaults to free providers with optional lookups enabled", () => {
  const config = testConfig();
  assert.equal(config.flightRoutesEnabled, true);
  assert.equal(config.aircraftPhotosEnabled, true);
  assert.equal(config.localNetworkOnly, true);
  assert.deepEqual(
    config.aircraftProviders.map((provider) => provider.name),
    ["adsb.lol", "adsb.fi", "airplanes.live"],
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

test("health reports free provider features and local registration", async (context) => {
  const server = createFlightLaneServer({ config: testConfig() });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const health = await fetch(`${baseUrl}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual((await health.json()).features, {
    liveAircraft: true,
    satelliteMaps: true,
    addressLookup: true,
    flightDetails: true,
    aircraftPhotos: true,
  });

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
  assert.equal((await second.json()).flightLaneSource, "ADSB.lol");
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

  assert.equal(result.provider, "adsb.fi");
  assert.deepEqual(result.failures, [{ provider: "adsb.lol", status: 403 }]);
  assert.match(requestedUrls[0], /^https:\/\/api\.adsb\.lol\/v2\/point\/28\.5\/-81\.6\/3\.476$/);
  assert.equal(requestedUrls[1], "https://opendata.adsb.fi/api/v3/lat/28.5/lon/-81.6/dist/3.476");
});

test("aircraft provider fallback reaches Airplanes.live after both ADSB providers fail", async () => {
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

  assert.equal(result.provider, "airplanes.live");
  assert.deepEqual(result.failures, [
    { provider: "adsb.lol", status: 429 },
    { provider: "adsb.fi", status: 429 },
  ]);
  assert.equal(requestedUrls[2], "https://api.airplanes.live/v2/point/28.5/-81.6/3.476");
});

test("Census geocoding returns the response shape the Roku parses", async (context) => {
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

test("satellite maps request the matching USGS bounding box and are cached", async (context) => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(new URL(url));
    return new Response(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), {
      headers: { "Content-Type": "image/jpeg", "Cache-Control": "max-age=0,must-revalidate" },
    });
  };
  const server = createFlightLaneServer({ config: testConfig(), fetchImpl });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const query = "/v1/map?latitude=0&longitude=0&zoom=1&size=256";
  const [first, second] = await Promise.all([fetch(baseUrl + query), fetch(baseUrl + query)]);
  const third = await fetch(baseUrl + query);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(third.headers.get("x-flightlane-cache"), "hit");
  assert.equal(third.headers.get("x-flightlane-attribution"), "USDA, USGS The National Map");
  assert.deepEqual([...new Uint8Array(await third.arrayBuffer())], [0xff, 0xd8, 0xff, 0xd9]);
  assert.equal(requestedUrls.length, 1);

  const [providerUrl] = requestedUrls;
  assert.equal(providerUrl.hostname, "basemap.nationalmap.gov");
  assert.equal(providerUrl.searchParams.get("size"), "512,512");
  // At zoom 1, 256 logical pixels span half the world: x and y from -1/4 to +1/4 of the circumference.
  const quarter = (Math.PI * 6378137) / 2;
  assert.deepEqual(
    providerUrl.searchParams.get("bbox").split(",").map(Number),
    [-quarter, -quarter, quarter, quarter].map((value) => Math.round(value * 100) / 100),
  );
  assert.equal(providerUrl.searchParams.has("key"), false);
});

test("flight routes come from adsbdb and unknown callsigns return no flights", async (context) => {
  const requestedUrls = [];
  const fetchImpl = async (url) => {
    requestedUrls.push(String(url));
    if (String(url).endsWith("/AAL100")) {
      return Response.json({
        response: {
          flightroute: {
            callsign_icao: "AAL100",
            callsign_iata: "AA100",
            airline: { name: "American Airlines" },
            origin: { iata_code: "JFK", icao_code: "KJFK", name: "John F Kennedy International Airport" },
            destination: { iata_code: "LHR", icao_code: "EGLL", name: "London Heathrow Airport" },
          },
        },
      });
    }
    return Response.json({ response: "unknown callsign" }, { status: 404 });
  };
  const server = createFlightLaneServer({ config: testConfig(), fetchImpl });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const known = await (await fetch(`${baseUrl}/v1/flights/AAL100`)).json();
  assert.equal(known.source, "adsbdb.com");
  assert.equal(known.flights[0].ident_iata, "AA100");
  assert.equal(known.flights[0].origin.code_iata, "JFK");
  assert.equal(known.flights[0].destination.code_icao, "EGLL");
  assert.equal(requestedUrls[0], "https://api.adsbdb.com/v0/callsign/AAL100");

  const unknown = await fetch(`${baseUrl}/v1/flights/N12345`);
  assert.equal(unknown.status, 200);
  assert.deepEqual((await unknown.json()).flights, []);
});
