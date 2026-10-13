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
    liveFlightStatus: false,
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

function flightAwareFetch({ totalCost = 1.25, usageStatus = 200 } = {}) {
  const requestedUrls = [];
  const fetchImpl = async (url, options = {}) => {
    const text = String(url);
    requestedUrls.push(text);
    if (text.startsWith("https://aeroapi.flightaware.com/aeroapi/account/usage")) {
      assert.equal(options.headers["x-apikey"], "fa-test-secret");
      if (usageStatus !== 200) return Response.json({ title: "error" }, { status: usageStatus });
      return Response.json({ total_cost: totalCost, total_pages: 250 });
    }
    if (text.startsWith("https://aeroapi.flightaware.com/")) {
      assert.equal(options.headers["x-apikey"], "fa-test-secret");
      return Response.json({
        flights: [{ ident: "AAL100", status: "En Route / On Time", origin: { code_iata: "JFK" } }],
      });
    }
    if (text.includes("/point/")) return Response.json({ ac: [], now: 1234567890000 });
    return Response.json({ response: "unknown callsign" }, { status: 404 });
  };
  const billedCalls = () =>
    requestedUrls.filter((url) => url.startsWith("https://aeroapi.flightaware.com/aeroapi/flights/"))
      .length;
  return { fetchImpl, requestedUrls, billedCalls };
}

async function flightAwareServer(context, overrides, fetchOptions) {
  const fake = flightAwareFetch(fetchOptions);
  const server = createFlightLaneServer({
    config: testConfig({ FLIGHTAWARE_API_KEY: "fa-test-secret", ...overrides }),
    fetchImpl: fake.fetchImpl,
  });
  context.after(() => server.close());
  const baseUrl = await listen(server);
  const lookup = async (callsign, manual) =>
    (await fetch(`${baseUrl}/v1/flights/${callsign}${manual ? "?manual=1" : ""}`)).json();
  return { ...fake, baseUrl, lookup };
}

test("without a FlightAware key the service never contacts AeroAPI", async (context) => {
  const fake = flightAwareFetch();
  const server = createFlightLaneServer({ config: testConfig(), fetchImpl: fake.fetchImpl });
  context.after(() => server.close());
  const baseUrl = await listen(server);

  const route = await (await fetch(`${baseUrl}/v1/flights/AAL100?manual=1`)).json();
  const nearby = await (
    await fetch(`${baseUrl}/v1/aircraft/nearby?latitude=28.5&longitude=-81.6&radiusMiles=4`)
  ).json();
  const health = await (await fetch(`${baseUrl}/health`)).json();

  assert.equal(route.liveStatusAvailable, false);
  assert.equal(nearby.flightAware, undefined);
  assert.equal(health.flightAwareSpend, undefined);
  assert.equal(fake.requestedUrls.some((url) => url.includes("flightaware")), false);
});

test("FlightAware is used only for manual selections, cached, and capped per day", async (context) => {
  const { lookup, requestedUrls, billedCalls } = await flightAwareServer(context, {
    FLIGHTAWARE_DAILY_LIMIT: "2",
  });

  const automatic = await lookup("AAL100", false);
  assert.equal(billedCalls(), 0);
  // Wait for the background usage check started by the automatic lookup.
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal((await lookup("AAL100", false)).liveStatusAvailable, true);
  assert.equal(automatic.source, undefined);

  const manual = await lookup("AAL100", true);
  assert.equal(manual.source, "FlightAware");
  assert.equal(manual.liveStatus, true);
  assert.equal(manual.flights[0].status, "En Route / On Time");
  assert.equal(
    requestedUrls.at(-1),
    "https://aeroapi.flightaware.com/aeroapi/flights/AAL100?max_pages=1",
  );

  await lookup("AAL100", true);
  assert.equal(billedCalls(), 1, "a repeat lookup is served from cache");

  await lookup("UAL1", true);
  assert.equal(billedCalls(), 2);

  const overLimit = await lookup("DAL1", true);
  assert.equal(billedCalls(), 2, "the daily limit blocks further billed calls");
  assert.equal(overLimit.liveStatus, undefined);
  assert.equal(overLimit.liveStatusAvailable, false);
  assert.equal(requestedUrls.at(-1), "https://api.adsbdb.com/v0/callsign/DAL1");
});

test("FlightAware usage is read for this month and reported to the Roku", async (context) => {
  const { baseUrl, lookup, requestedUrls } = await flightAwareServer(
    context,
    {},
    { totalCost: 5.5 },
  );
  await lookup("AAL100", true);
  const usageUrl = new URL(requestedUrls.find((url) => url.includes("/account/usage")));
  assert.equal(usageUrl.searchParams.get("start"), `${new Date().toISOString().slice(0, 7)}-01`);
  assert.equal(usageUrl.searchParams.get("all_keys"), "true");

  const nearby = await (
    await fetch(`${baseUrl}/v1/aircraft/nearby?latitude=28.5&longitude=-81.6&radiusMiles=4`)
  ).json();
  // 5.50 reported plus one billed page since the reading, at 5.50 / 250 per page.
  assert.deepEqual(nearby.flightAware, {
    state: "warning",
    monthToDateCost: 5.52,
    warning: 5,
    limit: 10,
  });
});

test("FlightAware calls stop at the spend limit or when usage cannot be read", async (context) => {
  const overLimit = await flightAwareServer(context, {}, { totalCost: 10.01 });
  const limited = await overLimit.lookup("AAL100", true);
  assert.equal(overLimit.billedCalls(), 0);
  assert.equal(limited.source, undefined);
  assert.equal(limited.liveStatusAvailable, false);

  const unreadable = await flightAwareServer(context, {}, { usageStatus: 401 });
  await unreadable.lookup("AAL100", true);
  assert.equal(unreadable.billedCalls(), 0, "billed calls pause when spend is unknown");

  assert.throws(
    () =>
      testConfig({ FLIGHTAWARE_API_SPEND_WARNING: "20", FLIGHTAWARE_API_SPEND_LIMIT: "10" }),
    /SPEND_WARNING/,
  );
  assert.equal(testConfig({ FLIGHTAWARE_CACHE_TTL: "60" }).flightAwareCacheSeconds, 3600);
});
