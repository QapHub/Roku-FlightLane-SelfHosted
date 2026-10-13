# Provider setup and usage controls

Provider products, allowances, prices, and license terms can change. Check each provider's current documentation before use. You are responsible for obtaining suitable access and following the applicable terms.

## Live aircraft positions

Flight Lane defaults to the [ADSB.lol API](https://api.adsb.lol/docs) point endpoint. ADSB.lol publishes its data under the Open Database License (ODbL) and needs no key; the Roku credits it under the radar whenever it supplies the positions shown. If the configured provider is blocked or temporarily unavailable, the local service falls back to ADSB.fi. A provider that refuses a request is skipped for 30 seconds after a 429 or error, or 30 minutes after a 403, so the service does not retry it on every refresh.

Relevant `.env.local` settings:

```dotenv
AIRCRAFT_API_BASE_URL=https://api.adsb.lol/v2
AIRCRAFT_CACHE_SECONDS=15
```

`AIRCRAFT_CACHE_SECONDS` is the minimum time between upstream requests for the same rounded location and radius. Multiple local Roku refreshes during that window reuse the in-memory response. At continuous use, the approximate maximum is `86,400 / AIRCRAFT_CACHE_SECONDS` upstream calls per day: 5,760 at the default 15 seconds, 2,880 at 30 seconds.

Backup provider requests use the same rounded location, radius, timeout, and cache window. They are only tried after an earlier provider fails, so normal use still starts with your configured `AIRCRAFT_API_BASE_URL`.

Provider limits differ:

- ADSB.lol and ADSB.fi do not publish a fixed daily allowance but rate-limit bursts; in testing, a few requests in quick succession returned 429, while one request every couple of seconds did not. The default 15-second cache stays well under that. Running other ADS-B tools from the same internet connection shares the same allowance.
- Airplanes.live now refuses API requests (HTTP 403) unless you contact them for access, so it is no longer a default fallback. If you are granted access, set `AIRCRAFT_API_BASE_URL=https://api.airplanes.live/v2` and follow their published limits.

The interface animates projected motion between responses, but a longer cache means less authoritative position correction.

## Address lookup

Address lookup uses the free [US Census Bureau geocoder](https://geocoding.geo.census.gov/geocoder/). It needs no account or key but matches US street addresses only, so include the street, city, state, and ZIP code. Lookup runs only when you enter an address, and results are cached in memory for 24 hours.

## Satellite maps

Satellite maps use public-domain USDA NAIP and USGS orthoimagery from [The National Map](https://www.usgs.gov/programs/national-geospatial-program/national-map). No account or key is needed. Coverage is limited to the United States; outside it, the map area is blank while the radar still works.

```dotenv
MAP_CACHE_SECONDS=86400
```

The local service requests one finished image per map view and keeps it in memory for `MAP_CACHE_SECONDS` (default 24 hours; `0` disables reuse). Simultaneous requests for the same image share one provider call. The Roku also snaps close-up map centers to a fixed grid, so a slow or parked aircraft reuses one image instead of requesting a new one every refresh. The imagery has no road or place labels.

## Flight route details

[adsbdb.com](https://www.adsbdb.com/) supplies optional origin and destination airports for a callsign. No key is needed.

```dotenv
ENABLE_FLIGHT_ROUTES=true
FLIGHT_DETAILS_CACHE_SECONDS=86400
```

These are the typical route for a flight number, not live flight status, so departure and arrival times are not available. Private and general-aviation callsigns usually have no route. Set `ENABLE_FLIGHT_ROUTES=false` to stop all route lookups, including FlightAware. The radar, altitude, speed, heading, phase, and projected motion still work from live position data.

### Optional: live status from FlightAware (billed)

[FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) adds live status and takeoff and landing times. **It is not free.** AeroAPI requires a billing account and charges per query; the Personal tier currently includes a small monthly usage credit (larger for ADS-B feeders), and usage beyond it is charged to your card. Check FlightAware's current pricing and terms before adding a key.

```dotenv
FLIGHTAWARE_API_KEY=your_aeroapi_key
FLIGHTAWARE_API_SPEND_WARNING=5
FLIGHTAWARE_API_SPEND_LIMIT=10
FLIGHTAWARE_CACHE_TTL=1440
FLIGHTAWARE_DAILY_LIMIT=500
```

The values shown are the defaults. With a key, FlightAware is the preferred route source for every selected aircraft, including the automatically tracked closest one, until the monthly spend limit is reached.

**Without a key, nothing is sent to FlightAware.** The service makes no AeroAPI requests of any kind, including usage checks, and the Roku shows no FlightAware notice.

With a key, the local service makes two kinds of AeroAPI request:

| Request | Billed | When |
| --- | --- | --- |
| `GET /account/usage?start=<first of this month>&all_keys=true` | No (FlightAware documents it as free) | At most every 10 minutes while the app is refreshing, and before a billed lookup if the last reading is 10 minutes old |
| `GET /flights/<callsign>?max_pages=1` | Yes | For each newly selected aircraft (automatic or manual) whose callsign is not cached, when every check below passes |

Before each billed lookup, the service checks, in order:

1. **Cache:** each callsign's result is reused for `FLIGHTAWARE_CACHE_TTL` minutes (default 1440, 24 hours), including callsigns FlightAware does not know.
2. **Monthly spend:** month-to-date spend comes from `total_cost` in the usage response, covering every key on your account, before volume discounts. FlightAware updates it every 10 minutes, so the service adds calls made since the last reading at your account's average cost per result page. The Roku shows the spend above **FLIGHT PHASE**, for example `FlightAware API: $5.40 of $10`. It turns amber at `FLIGHTAWARE_API_SPEND_WARNING` (default $5). At `FLIGHTAWARE_API_SPEND_LIMIT` (default $10) it turns red and reads `· paused`, and billed lookups stop until next month.
3. **Spend known:** if usage cannot be read for 30 minutes (wrong key, outage), billed lookups pause rather than risk unmonitored charges.
4. **Daily cap:** at most `FLIGHTAWARE_DAILY_LIMIT` billed lookups per UTC day (default 500), as a backstop against bursts between 10-minute usage readings.

Whenever FlightAware is skipped, fails, or has no match, the route comes from free adsbdb.com data.

Expect spend to scale with how often the selected aircraft changes. Near a busy airport, automatic tracking can select a new aircraft every minute or two, which is several hundred billed lookups a day; the default $10 limit then stops FlightAware within days, after which routes continue from adsbdb.com until the next month.

The spend limit is a safeguard, not a guarantee: FlightAware's figure can lag, and calls in flight when the limit is crossed still complete. Set it below what you are willing to pay, and set any usage alerts AeroAPI offers. The daily count is kept in memory, so restarting the service resets it. A long cache can show an earlier flight's times if the same flight number flies again within the cache window.

Treat the key like a password: it stays in `.env.local` on your computer, is never compiled into the Roku app, and should be rotated in the AeroAPI portal if it is ever disclosed.

## Aircraft photos

Flight Lane requests photo metadata from the public Planespotters.net endpoint and displays only a validated HTTPS thumbnail with its attribution and source link.

```dotenv
ENABLE_AIRCRAFT_PHOTOS=true
AIRCRAFT_PHOTO_CACHE_SECONDS=3600
```

Set `ENABLE_AIRCRAFT_PHOTOS=false` to turn this feature off. Photos are not downloaded to disk or bulk-stored by Flight Lane.
