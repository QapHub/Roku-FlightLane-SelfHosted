# Troubleshooting

Start with:

```sh
npm run diagnose
```

## The local service does not start

- Confirm `node --version` is 20 or newer.
- Confirm `.env.local` exists.
- Check whether another process is using port 8787:

  ```sh
  # macOS / Linux
  lsof -nP -iTCP:8787 -sTCP:LISTEN

  # Windows PowerShell
  Get-NetTCPConnection -LocalPort 8787 -ErrorAction SilentlyContinue
  ```

- Change `LOCAL_API_PORT` and the port in `FLIGHTLANE_API_URL` together if needed.

## The Roku cannot connect

- Keep `npm run api` running.
- Use the computer's LAN address—not `localhost`—for `FLIGHTLANE_API_URL`.
- Confirm the Roku and computer are on the same non-guest network.
- Disconnect a VPN temporarily if it blocks local networking.
- Allow Node.js through the firewall: on macOS, allow incoming connections for `node` in **System Settings > Network > Firewall > Options**; on Windows, allow it on Private networks only.
- On macOS, if `npm run deploy` or `npm run debug` cannot reach the Roku, confirm your terminal app has **Local Network** access in **System Settings > Privacy & Security > Local Network**.
- A sleeping Mac stops serving the Roku. Run `caffeinate -i npm run api` or adjust Energy settings.
- From another device on the same network, open `http://COMPUTER_IP:8787/health`.
- Rebuild and reinstall after changing `FLIGHTLANE_API_URL`; it is the only service setting compiled into the Roku ZIP.

## Address lookup fails

- The Census geocoder matches US street addresses only. Include street, city, state, and ZIP code.
- Try the address at [geocoding.geo.census.gov](https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?form). If it fails there, try a nearby street address.
- Check the local service health response: `addressLookup` should be `true`.

## Satellite map is blank

- Imagery covers the United States only.
- Watch the `npm run api` terminal for `provider_error` messages with `"feature":"Satellite map"`; the USGS National Map service is occasionally down for maintenance.
- Restarting the local service clears its in-memory map cache.

## Aircraft are missing

- Verify the selected radius in app settings.
- Check that the live-aircraft provider covers the area.
- If ADSB.lol is unavailable, the local service should try ADSB.fi automatically. Watch the `npm run api` terminal for `provider_fallback` and `provider_cooldown` messages. A 429 means the provider is rate-limiting your internet connection; a 403 from Airplanes.live means it requires approved access.
- If `.env.local` sets `AIRCRAFT_API_BASE_URL=https://api.airplanes.live/v2` and you have not been granted access, change it to `https://api.adsb.lol/v2`.
- Keep the app open through another refresh cycle.
- Set `PROVIDER_POLL_SECONDS` (or the **Provider polling** setting on the Roku) within your provider allowance (ADSB.fi: 1 request per second; ADSB.lol throttles faster than about one every 2 seconds). Longer values reduce upstream usage but make trails coarser and corrections slower.
- Use `npm run debug` and look for the sanitized nearby-provider HTTP status and raw/usable counts.

Small aircraft may not broadcast usable ADS-B positions, may be outside receiver coverage, or may omit coordinates. Flight Lane cannot display an aircraft that the configured provider does not return with a usable position.

## Route or destination is unavailable

- Confirm `ENABLE_FLIGHT_ROUTES` is not `false`. The local service health response should report `flightDetails: true`.
- Routes come from adsbdb.com's callsign database. Private, general-aviation, charter, and new flight numbers often have no entry.
- The route shown is the typical route for that flight number; a diverted or substituted flight can differ.
- With a FlightAware key, routes show `· FlightAware` when they come from FlightAware. If they switch to `· adsbdb.com`, check the notice above **FLIGHT PHASE** and the `npm run api` terminal:
  - `FlightAware API: $X of $Y · paused` (red): month-to-date spend reached `FLIGHTAWARE_API_SPEND_LIMIT`. Raise the limit or wait for the next month.
  - `FlightAware API: usage unknown · paused`: the usage endpoint could not be read for 30 minutes, so billed lookups are paused. Look for `"feature":"FlightAware usage"` errors; a 401 or 403 usually means the key is wrong or billing is not set up.
  - `flightaware_daily_limit_reached` in the terminal: `FLIGHTAWARE_DAILY_LIMIT` was reached for the UTC day.

## `npm run deploy` cannot connect on macOS

`curl: (7) Failed to connect to <ROKU_IP> port 80 after 1 ms` while the Roku developer page opens in your browser means macOS is blocking your terminal app from the local network. Open **System Settings > Privacy & Security > Local Network**, enable your terminal app (Terminal, iTerm, VS Code, and so on), then quit and reopen it. Until then, run `npm run build` and upload `dist/flight-lane.zip` through the developer page.

## The Roku still shows old text after an update

The Roku runs whatever ZIP was last installed. Run `npm run build` (or `npm run deploy`) after pulling changes, and upload the new `dist/flight-lane.zip`; uploading an older ZIP keeps the older app. Restart `npm run api` too, so the local service runs the new code.

## Another development app disappeared

This is a Roku platform limitation: only one sideloaded development app can be present. Installing Flight Lane replaces the previous sideload, and installing another development ZIP replaces Flight Lane.

## View the BrightScript console

```sh
npm run debug
```

The helper redacts common key, address, coordinate, and bearer-token URL fields before printing. Still review logs before sharing them publicly.
