# Provider setup and usage controls

Provider products, allowances, prices, and license terms can change. Check each provider's current documentation before use. You are responsible for obtaining suitable access and following the applicable terms.

## Live aircraft positions

Flight Lane defaults to the [Airplanes.live REST API](https://airplanes.live/api-guide/) point endpoint. No key is currently required for that endpoint.

Relevant `.env.local` settings:

```dotenv
AIRCRAFT_API_BASE_URL=https://api.airplanes.live/v2
AIRCRAFT_CACHE_SECONDS=15
```

`AIRCRAFT_CACHE_SECONDS` is the minimum time between upstream requests for the same rounded location and radius. Multiple local Roku refreshes during that window reuse the in-memory response.

Airplanes.live currently lists:

- a one-request-per-second REST limit;
- 500 requests per day for free access;
- 8,640 requests per day for contributor access.

At continuous use, the approximate maximum is:

```text
86,400 / AIRCRAFT_CACHE_SECONDS
```

Examples:

| Cache | Maximum upstream calls per day | Suggested use |
| --- | ---: | --- |
| 180 seconds | 480 | Fits the currently listed free daily allowance |
| 30 seconds | 2,880 | Requires an access level that permits it |
| 15 seconds | 5,760 | Smoother updates; requires suitable access |
| 10 seconds | 8,640 | Matches the currently listed contributor allowance ceiling |

The interface animates projected motion between responses, but a longer cache means less authoritative position correction. Do not set a shorter interval than your provider access permits.

## Satellite maps and address lookup

Create a Google Maps Platform project and enable billing. Enable:

- [Maps Static API](https://developers.google.com/maps/documentation/maps-static/get-api-key)
- [Geocoding API](https://developers.google.com/maps/documentation/geocoding/get-api-key)

Create an API key and add:

```dotenv
GOOGLE_MAPS_API_KEY=your_maps_key
GOOGLE_GEOCODING_API_KEY=your_geocoding_key
```

You may use one key for both entries. If `GOOGLE_GEOCODING_API_KEY` is blank, the service falls back to `GOOGLE_MAPS_API_KEY`.

Recommended controls in Google Maps Platform:

- apply API restrictions so the key can call only Maps Static API and Geocoding API;
- set quota alerts and budgets;
- if your home has a stable public IP, consider an IP application restriction;
- never put the key directly in BrightScript or commit `.env.local`.

Maps and first-launch address entry will not work without these APIs. Live aircraft data can still work after a location is already saved.

## Flight route details

[FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) supplies optional origin, destination, timing, and status data.

```dotenv
FLIGHTAWARE_API_KEY=your_aeroapi_key
FLIGHT_DETAILS_CACHE_SECONDS=900
```

Leave the key blank to disable this enrichment. The radar, altitude, speed, heading, phase, and projected motion still work from live position data.

AeroAPI may charge by request or result set. Flight Lane caches a callsign's successful response for 15 minutes by default. Increase `FLIGHT_DETAILS_CACHE_SECONDS` to reduce lookups, especially near a busy airport. Review usage in the AeroAPI portal and configure the account controls available to you.

## Aircraft photos

Flight Lane requests photo metadata from the public Planespotters.net endpoint and displays only a validated HTTPS thumbnail with its attribution and source link.

```dotenv
ENABLE_AIRCRAFT_PHOTOS=true
AIRCRAFT_PHOTO_CACHE_SECONDS=3600
```

Set `ENABLE_AIRCRAFT_PHOTOS=false` to turn this feature off. Photos are not downloaded to disk or bulk-stored by Flight Lane.
