# Provider setup and usage controls

Provider products, allowances, prices, and license terms can change. Check each provider's current documentation before use. You are responsible for obtaining suitable access and following the applicable terms.

## Live aircraft positions

Flight Lane defaults to the [ADSB.lol API](https://api.adsb.lol/docs) point endpoint. ADSB.lol publishes its data under the Open Database License (ODbL) and needs no key; the Roku credits it under the radar whenever it supplies the positions shown. If the configured provider is blocked or temporarily unavailable, the local service falls back to ADSB.fi and then Airplanes.live.

Relevant `.env.local` settings:

```dotenv
AIRCRAFT_API_BASE_URL=https://api.adsb.lol/v2
AIRCRAFT_CACHE_SECONDS=15
```

`AIRCRAFT_CACHE_SECONDS` is the minimum time between upstream requests for the same rounded location and radius. Multiple local Roku refreshes during that window reuse the in-memory response. At continuous use, the approximate maximum is `86,400 / AIRCRAFT_CACHE_SECONDS` upstream calls per day: 5,760 at the default 15 seconds, 2,880 at 30 seconds.

Backup provider requests use the same rounded location, radius, timeout, and cache window. They are only tried after an earlier provider fails, so normal use still starts with your configured `AIRCRAFT_API_BASE_URL`.

Provider limits differ:

- ADSB.lol and ADSB.fi do not currently publish a fixed daily allowance, but may throttle heavy use. ADSB.fi asks for no more than one request per second.
- Airplanes.live lists a one-request-per-second limit, 500 requests per day for free access, and 8,640 per day for contributor access. If you set it as your primary provider, use an `AIRCRAFT_CACHE_SECONDS` of 180 or more on free access.

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

These are the typical route for a flight number, not live flight status, so departure and arrival times are not available. Private and general-aviation callsigns usually have no route. Set `ENABLE_FLIGHT_ROUTES=false` to stop sending selected callsigns to adsbdb.com. The radar, altitude, speed, heading, phase, and projected motion still work from live position data.

## Aircraft photos

Flight Lane requests photo metadata from the public Planespotters.net endpoint and displays only a validated HTTPS thumbnail with its attribution and source link.

```dotenv
ENABLE_AIRCRAFT_PHOTOS=true
AIRCRAFT_PHOTO_CACHE_SECONDS=3600
```

Set `ENABLE_AIRCRAFT_PHOTOS=false` to turn this feature off. Photos are not downloaded to disk or bulk-stored by Flight Lane.
