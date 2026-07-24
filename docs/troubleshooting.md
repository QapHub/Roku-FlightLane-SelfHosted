# Troubleshooting

Start with:

```powershell
npm run diagnose
```

## The local service does not start

- Confirm `node --version` is 20 or newer.
- Confirm `.env.local` exists.
- Check whether another process is using port 8787:

  ```powershell
  Get-NetTCPConnection -LocalPort 8787 -ErrorAction SilentlyContinue
  ```

- Change `LOCAL_API_PORT` and the port in `FLIGHTLANE_API_URL` together if needed.

## The Roku cannot connect

- Keep `npm run api` running.
- Use the computer's LAN address—not `localhost`—for `FLIGHTLANE_API_URL`.
- Confirm the Roku and computer are on the same non-guest network.
- Disconnect a VPN temporarily if it blocks local networking.
- Allow Node.js through Windows Firewall on Private networks only.
- From another device on the same network, open `http://COMPUTER_IP:8787/health`.
- Rebuild and reinstall after changing `FLIGHTLANE_API_URL`; it is the only service setting compiled into the Roku ZIP.

## Address lookup fails

- Enable the Google Geocoding API and billing.
- Confirm the API restriction permits Geocoding API.
- Check the local service health response: `addressLookup` should be `true`.
- Include street, city, state, and ZIP code.

## Satellite map is blank

- Enable Maps Static API and billing.
- Confirm the key's API restrictions include Maps Static API.
- Check the local service health response: `satelliteMaps` should be `true`.
- Google may reject requests when quota or billing is unavailable.

## Aircraft are missing

- Verify the selected radius in app settings.
- Check that the live-aircraft provider covers the area.
- Keep the app open through another refresh cycle.
- Set `AIRCRAFT_CACHE_SECONDS` within your provider allowance. Longer values reduce upstream usage but delay authoritative corrections.
- Use `npm run debug` and look for the sanitized nearby-provider HTTP status and raw/usable counts.

Small aircraft may not broadcast usable ADS-B positions, may be outside receiver coverage, or may omit coordinates. Flight Lane cannot display an aircraft that the configured provider does not return with a usable position.

## Route or destination is unavailable

- `FLIGHTAWARE_API_KEY` is optional; confirm it is present if route details are wanted.
- Check the local service health response: `flightDetails` should be `true`.
- Some private, general-aviation, blocked, or incomplete flights have no matching public route.
- FlightAware errors can also indicate account limits, billing, or a key restriction.

## Another development app disappeared

This is a Roku platform limitation: only one sideloaded development app can be present. Installing Flight Lane replaces the previous sideload, and installing another development ZIP replaces Flight Lane.

## View the BrightScript console

```powershell
npm run debug
```

The helper redacts common key, address, coordinate, and bearer-token URL fields before printing. Still review logs before sharing them publicly.
