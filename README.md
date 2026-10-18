# Flight Lane for Roku — self-hosted

![Flight Lane icon](images/flightlane-icon-v2_HD.png)

Flight Lane turns a Roku into a live aircraft radar for the location you choose. It shows nearby aircraft, altitude, ground speed, heading, estimated flight phase, route details, projected movement, satellite maps, aircraft photos, and a rolling 24-hour flyover count.

This repository is the self-hosted edition. A small service runs on a computer inside your home network and talks to the data providers on the Roku's behalf. Every provider is free and needs no API key. There is no hosted Flight Lane account, access code, telemetry service, or bundled provider credential.

> Flight positions and projected paths are estimates. Never use Flight Lane for navigation, separation, emergency response, or any safety-critical decision.

## What you need

- A Roku TV or player running Roku OS 15.1 or newer
- A macOS, Windows 10/11, or Linux computer on the same private network as the Roku
- [Node.js 20 or newer](https://nodejs.org/en/download)
- A free [Roku developer account](https://developer.roku.com/)
- Roku developer mode enabled

All helper scripts are plain Node.js, so the same `npm run` commands work in macOS Terminal, Windows PowerShell, and Linux shells. Deployment also uses `curl`, which is built into macOS and Windows 10/11.

## Quick start

1. Clone this repository and install the development dependency:

   ```sh
   git clone https://github.com/QapHub/Roku-FlightLane-SelfHosted.git
   cd Roku-FlightLane-SelfHosted
   npm install
   npm run setup
   ```

2. Open `.env.local` and replace the example values:

   ```dotenv
   FLIGHTLANE_API_URL=http://YOUR_COMPUTER_LAN_IP:8787
   ROKU_DEVICE_IP=YOUR_ROKU_IP
   ```

   `FLIGHTLANE_API_URL` must use the computer's private-network address, such as `http://192.168.1.25:8787`. Do not use `localhost`; from the Roku, `localhost` means the Roku itself.

3. Start the local service and leave this terminal open:

   ```sh
   npm run serve
   ```

   `npm run serve` restarts the service automatically if it crashes or hangs. See [Starting and restarting the local service](#starting-and-restarting-the-local-service).

4. Open a second terminal and install Flight Lane on the Roku:

   ```sh
   npm run deploy
   ```

   Enter the Roku developer password when prompted. The password is held only in memory for that installation and is not saved.

5. Launch Flight Lane and enter the address to monitor. The resulting location is saved in the Roku app's local registry.

## Starting and restarting the local service

The Roku needs the local service running whenever Flight Lane is in use. Start it from the repository folder in one of two ways:

| Command | Use when |
| --- | --- |
| `npm run serve` | **Recommended for everyday use.** Runs the service and restarts it automatically if it crashes, is killed, or stops answering its `/health` check (three missed checks, 20 seconds apart). Restarts back off from 1 to 60 seconds. |
| `npm run api` | Runs the service directly, without automatic restarts. Useful while troubleshooting. |

Leave that terminal open. To stop the service, press **Ctrl+C** in it (with `npm run serve`, this stops both the supervisor and the service).

**Restart the service after any change to `.env.local` or after pulling new code:** press Ctrl+C, then run `npm run serve` (or `npm run api`) again. Settings that are compiled into the Roku app (`FLIGHTLANE_API_URL`, `RADIUS_MILES`, `REFRESH_SECONDS`, `SHOW_FLYOVER_COUNT`, `TRAIL_MINUTES`, `PROVIDER_POLL_SECONDS` defaults) also need `npm run deploy`, or `npm run build` and a manual upload of `dist/flight-lane.zip`.

On a Mac, keep the computer awake while the service runs with `caffeinate -i npm run serve`. Check that everything is reachable with `npm run diagnose`.

For the complete device steps, read [Roku setup and sideloading](docs/roku-setup.md). For data sources and usage limits, read [Provider setup](docs/provider-setup.md).

## Useful commands

| Command | Purpose |
| --- | --- |
| `npm run setup` | Create `.env.local` and show possible computer LAN addresses |
| `npm run serve` | Start the local Flight Lane service and restart it automatically on a crash or hang |
| `npm run api` | Start the local Flight Lane service without automatic restarts |
| `npm run build` | Create `dist/flight-lane.zip` |
| `npm run deploy` | Build and sideload the main Roku app |
| `npm run build:screensaver` | Create the standalone screensaver ZIP |
| `npm run diagnose` | Check local service and Roku connectivity |
| `npm run debug` | Stream the Roku BrightScript console with sensitive URL fields redacted |
| `npm run check` | Run tests, compile BrightScript, build both ZIPs, and scan the output |

## How data moves

```text
Roku app
  |
  | private home network
  v
Local Flight Lane service on your computer
  |-- live aircraft positions
  |-- satellite map and address lookup
  |-- optional flight route details
  `-- optional aircraft photo metadata
```

Only `FLIGHTLANE_API_URL` is compiled into the Roku ZIP. The Roku never contacts providers directly; the local service makes every provider request.

The local service:

- accepts clients from private-network addresses by default;
- validates every coordinate, radius, zoom, callsign, and registration;
- limits request and response sizes;
- keeps short-lived data in memory to reduce duplicate provider calls;
- tries ADSB.lol and ADSB.fi if the configured live-aircraft provider is unavailable;
- does not write addresses, coordinates, device identifiers, or provider responses to disk;
- reports only feature availability from `/health`.

Never forward port `8787` from your router or expose it directly to the internet.

## Provider usage

The Roku can refresh its local display more often than the service calls a provider. `REFRESH_SECONDS` controls Roku-to-computer refreshes; `PROVIDER_POLL_SECONDS` (default 5, also changeable in the app's settings) sets how often the local service polls the live-aircraft provider while a Roku is active, which also sets how detailed the aircraft trails on the radar are. `TRAIL_MINUTES` (default 5) sets how much flown track is drawn behind aircraft; 0 turns trails off.

Flight Lane tries the configured live-aircraft provider (ADSB.lol by default) first. If that provider is blocked or temporarily unavailable, the local service falls back to ADSB.fi. A provider that refuses requests is skipped for a while (30 seconds after rate limiting, 30 minutes after a 403) instead of being retried on every refresh. A 15-second cache makes at most 5,760 upstream calls during 24 hours of continuous use. See [Provider setup](docs/provider-setup.md) for each provider's limits before leaving the app running continuously.

Every data provider Flight Lane uses by default is free and needs no account or key:

| Data | Provider |
| --- | --- |
| Live aircraft positions | ADSB.lol, with ADSB.fi as fallback |
| Satellite imagery | USDA / USGS The National Map (public domain, US coverage) |
| Address lookup | US Census Bureau geocoder (US addresses) |
| Flight routes (optional) | adsbdb.com |
| Live flight status (optional, billed) | FlightAware AeroAPI, only if you add a key; preferred for routes until a monthly spend limit, then adsbdb.com |
| Aircraft photos (optional) | Planespotters.net |

The Roku shows which provider supplied the current aircraft positions and imagery below the radar, the route source with each route, and the photographer credit with each photo.

## Important Roku limitation

A Roku holds only one sideloaded development app at a time. Installing another development ZIP replaces Flight Lane, and installing the standalone Flight Lane screensaver replaces the main development app. Store-installed apps are separate from this sideload slot.

## Privacy

The street address is sent from the Roku to your computer and forwarded only to the US Census Bureau geocoder. Flight Lane stores the selected address and coordinates on the Roku. The local service keeps a geocoding result only in memory and loses it when the service restarts.

Nearby coordinates are sent to the configured live-aircraft provider or, when that provider fails, to ADSB.lol or ADSB.fi. Map coordinates are sent to the USGS National Map. A selected callsign may be sent to adsbdb.com (or, if you add a FlightAware key, to FlightAware), and a selected aircraft registration may be sent to Planespotters.net. Each provider's terms and privacy policy apply.

Flight Lane contains no analytics or advertising SDK. See [SECURITY.md](SECURITY.md) for security guidance.

## License

The Flight Lane source is available under the [MIT License](LICENSE). Aircraft, map, route, and photo data remain subject to their providers' terms and licenses.
