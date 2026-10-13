# Provider setup and usage controls

Provider products, allowances, prices, and license terms can change. Check each provider's current documentation before use. You are responsible for obtaining suitable access and following the applicable terms.

## Live aircraft positions

Flight Lane defaults to the [ADSB.lol API](https://api.adsb.lol/docs) point endpoint. ADSB.lol publishes its data under the Open Database License (ODbL) and needs no key; the Roku credits it under the radar whenever it supplies the positions shown. If the configured provider is blocked or temporarily unavailable, the local service falls back to ADSB.fi. A provider that refuses a request is skipped for 30 seconds after a 429 or error, or 30 minutes after a 403, so the service does not retry it on every refresh.

Relevant `.env.local` settings:

```dotenv
AIRCRAFT_API_BASE_URL=https://api.adsb.lol/v2
PROVIDER_POLL_SECONDS=5
```

`PROVIDER_POLL_SECONDS` (default 5; `AIRCRAFT_CACHE_SECONDS` is accepted as its earlier name) is the time between upstream requests for your location and radius. It is the default for the **Provider polling** setting on the Roku (2, 5, 10, 15, 30, or 60 seconds); a value chosen there is sent with each request and takes precedence. While a Roku has requested aircraft in the last two minutes, the local service polls at this rate in the background, independent of the Roku's `REFRESH_SECONDS`, so it can record each aircraft's track densely. Polling stops two minutes after the Roku stops asking (for example, when the TV is off). Roku refreshes in between reuse the latest in-memory response. At continuous use that is up to `86,400 / PROVIDER_POLL_SECONDS` upstream calls per day: 17,280 at 5 seconds, 43,200 at 2 seconds.

Backup provider requests use the same rounded location, radius, timeout, and cache window. They are only tried after an earlier provider fails, so normal use still starts with your configured `AIRCRAFT_API_BASE_URL`.

Provider limits differ:

- ADSB.fi documents a limit of 1 request per second on its public endpoints.
- ADSB.lol publishes no limit but rate-limits bursts: in testing, one request every 2 seconds was accepted while one per second was refused (429) after a few requests. A 429 skips ADSB.lol for 30 seconds and uses ADSB.fi.
- Both are free community services, and other ADS-B tools on the same internet connection share the allowance. If you see frequent `provider_cooldown` messages, choose a longer polling interval (10 seconds still gives useful trails).
- Airplanes.live now refuses API requests (HTTP 403) unless you contact them for access, so it is no longer a default fallback. If you are granted access, set `AIRCRAFT_API_BASE_URL=https://api.airplanes.live/v2` and follow their published limits.

### Aircraft icons

Each aircraft is drawn as a small icon pointing along its heading:

| Icon | Shown for |
| --- | --- |
| Helicopter | ADS-B category A7 (rotorcraft), or a known helicopter type such as H60, B06, or EC35 |
| Fighter jet | Aircraft flagged as military in the provider's database (red, including military helicopters) |
| Airliner | Categories A3 to A6 (large, heavy, and high-performance) |
| Ground vehicle | Categories C1 to C3 (airport vehicles and obstacles) |
| Light aircraft | Categories A1 and A2, and anything unclassified |

Icons are blue, red for military aircraft, and amber for the selected aircraft.

### Tracks on the radar

The local service keeps each aircraft's reported positions for five minutes, in memory only. Each refresh sends the Roku a thinned trail (about one point every 10 seconds, plus points where the aircraft turned) and a turn rate worked out from its recent tracks. The Roku draws:

- **where the aircraft flew:** a fading line through its earlier positions. `TRAIL_MINUTES` (default 5) and the **Aircraft trails** setting on the Roku (Off, 1, 2, or 5 minutes) set the length for the selected aircraft; other aircraft show at most the last 80 seconds of it;
- **where it is heading:** a path curving with the current turn, 90 seconds ahead for the selected aircraft and 60 for others. When the aircraft reports an autopilot-selected heading, the curve straightens out on that heading.

Markers move along the same curve between updates, and the closest-approach estimate uses it too. Trails start when an aircraft enters your radius and reset when the local service restarts.

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

[FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) adds live status and takeoff and landing times. Times are shown in the Roku's own time zone (**Settings > System > Time** on the Roku), the same as the clock in the header. **It is not free.** AeroAPI requires a billing account and charges per query; the Personal tier currently includes a small monthly usage credit (larger for ADS-B feeders), and usage beyond it is charged to your card. Check FlightAware's current pricing and terms before adding a key.

```dotenv
FLIGHTAWARE_API_KEY=your_aeroapi_key
FLIGHTAWARE_API_SPEND_WARNING=5
FLIGHTAWARE_API_SPEND_LIMIT=10
FLIGHTAWARE_CACHE_TTL=1440
FLIGHTAWARE_DAILY_LIMIT=500
```

The values shown are the defaults, except `FLIGHTAWARE_API_SPEND_WARNING`, which is unset by default. With a key, FlightAware is the preferred route source for every selected aircraft, including the automatically tracked closest one, until the monthly spend limit is reached.

**Without a key, nothing is sent to FlightAware.** The service makes no AeroAPI requests of any kind, including usage checks, and the Roku shows no FlightAware notice.

With a key, the local service makes two kinds of AeroAPI request:

| Request | Billed | When |
| --- | --- | --- |
| `GET /account/usage?start=<first of this month>&all_keys=true` | No (FlightAware documents it as free) | At most every 10 minutes while the app is refreshing, and before a billed lookup if the last reading is 10 minutes old |
| `GET /flights/<callsign>?max_pages=1` | Yes | For each newly selected aircraft (automatic or manual) whose callsign is not cached, when every check below passes |

Before each billed lookup, the service checks, in order:

1. **Cache:** each callsign's result is reused for `FLIGHTAWARE_CACHE_TTL` minutes (default 1440, 24 hours), including callsigns FlightAware does not know.
2. **Monthly spend:** month-to-date spend comes from `total_cost` in the usage response, covering every key on your account, before volume discounts. FlightAware updates it every 10 minutes, so the service adds calls made since the last reading at your account's average cost per result page. When `FLIGHTAWARE_API_SPEND_WARNING` is set, the Roku shows the spend above **FLIGHT PHASE**, for example `FlightAware (12%) API: $5.40 of $10`, turning amber at that amount. When it is unset or blank, nothing about spending appears on screen, but the limit is still enforced. At `FLIGHTAWARE_API_SPEND_LIMIT` (default $10) it turns red and reads `· paused`, and billed lookups stop until next month.
3. **Spend known:** if usage cannot be read for 30 minutes (wrong key, outage), billed lookups pause rather than risk unmonitored charges.
4. **Daily cap:** at most `FLIGHTAWARE_DAILY_LIMIT` billed lookups per UTC day (default 500), as a backstop against bursts between 10-minute usage readings. Every on-screen FlightAware mention shows the share of today's cap used, for example `FlightAware (12%) API: $5.40 of $10` and `En Route · FlightAware (12%)`.

FlightAware returns every recent and scheduled flight for a flight number, often on different routes (Southwest, for example, reuses numbers across routes and lists each leg of a multi-stop flight separately). The service shows the one being flown now: the flight that has departed and not yet landed, or otherwise the one whose departure-to-arrival window is closest to the current time. It chooses at display time, so the choice stays current within the cache window, but the status and times shown are as of the cached lookup.

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
