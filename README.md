# Flight Lane for Roku — self-hosted

![Flight Lane icon](images/flightlane-icon-v2_HD.png)

Flight Lane turns a Roku into a live aircraft radar for the location you choose. It shows nearby aircraft, altitude, ground speed, heading, estimated flight phase, route details, projected movement, satellite maps, aircraft photos, and a rolling 24-hour flyover count.

This repository is the self-hosted edition. A small service runs on a computer inside your home network and keeps all provider API keys off the Roku. There is no hosted Flight Lane account, access code, telemetry service, or bundled provider credential.

> Flight positions and projected paths are estimates. Never use Flight Lane for navigation, separation, emergency response, or any safety-critical decision.

## What you need

- A Roku TV or player running Roku OS 15.1 or newer
- A Windows 10 or 11 computer on the same private network as the Roku
- [Node.js 20 or newer](https://nodejs.org/en/download)
- A free [Roku developer account](https://developer.roku.com/)
- Roku developer mode enabled
- A Google Maps Platform project with Maps Static API and Geocoding API enabled
- Optional: a FlightAware AeroAPI key for origin, destination, and status enrichment

The local service itself also runs on macOS or Linux with Node.js 20+, but the included one-command Roku packaging and deployment scripts currently target Windows PowerShell.

## Quick start

1. Clone this repository and install the development dependency:

   ```powershell
   git clone https://github.com/QapHub/Roku-FlightLane-SelfHosted.git
   cd Roku-FlightLane-SelfHosted
   npm install
   npm run setup
   ```

2. Open `.env.local` and replace the example values:

   ```dotenv
   FLIGHTLANE_API_URL=http://YOUR_COMPUTER_LAN_IP:8787
   ROKU_DEVICE_IP=YOUR_ROKU_IP
   GOOGLE_MAPS_API_KEY=your_key
   GOOGLE_GEOCODING_API_KEY=your_key
   FLIGHTAWARE_API_KEY=optional_key
   ```

   `FLIGHTLANE_API_URL` must use the computer's private-network address, such as `http://192.168.1.25:8787`. Do not use `localhost`; from the Roku, `localhost` means the Roku itself.

3. Start the local service and leave this terminal open:

   ```powershell
   npm run api
   ```

4. Open a second terminal and install Flight Lane on the Roku:

   ```powershell
   npm run deploy
   ```

   Enter the Roku developer password when prompted. The password is held only in memory for that installation and is not saved.

5. Launch Flight Lane and enter the address to monitor. The resulting location is saved in the Roku app's local registry.

For the complete device steps, read [Roku setup and sideloading](docs/roku-setup.md). For API accounts and cost controls, read [Provider setup](docs/provider-setup.md).

## Useful commands

| Command | Purpose |
| --- | --- |
| `npm run setup` | Create `.env.local` and show possible computer LAN addresses |
| `npm run api` | Start the local Flight Lane service |
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

Only `FLIGHTLANE_API_URL` is compiled into the Roku ZIP. Provider keys remain in the ignored `.env.local` file and are attached to provider requests by the local service.

The local service:

- accepts clients from private-network addresses by default;
- validates every coordinate, radius, zoom, callsign, and registration;
- limits request and response sizes;
- keeps short-lived data in memory to reduce duplicate provider calls;
- does not write addresses, coordinates, device identifiers, or provider responses to disk;
- reports only feature availability—not key values—from `/health`.

Never forward port `8787` from your router or expose it directly to the internet.

## Provider usage

The Roku can refresh its local display more often than the service calls a provider. `REFRESH_SECONDS` controls Roku-to-computer refreshes; `AIRCRAFT_CACHE_SECONDS` controls upstream live-aircraft refreshes.

Airplanes.live currently documents a one-request-per-second limit and plan-specific daily allowances. A cache of 180 seconds is at most 480 upstream calls during 24 hours of continuous use; a 15-second cache can make up to 5,760. Choose a value permitted by your current access level and use. See [Provider setup](docs/provider-setup.md) before leaving the app running continuously.

FlightAware enrichment is optional and may be billed. It is disabled when `FLIGHTAWARE_API_KEY` is blank. Successful detail responses are cached for 15 minutes by default.

## Important Roku limitation

A Roku holds only one sideloaded development app at a time. Installing another development ZIP replaces Flight Lane, and installing the standalone Flight Lane screensaver replaces the main development app. Store-installed apps are separate from this sideload slot.

## Privacy

The street address is sent from the Roku to your computer and forwarded to Google only for geocoding. Flight Lane stores the selected address and coordinates on the Roku. The local service keeps a geocoding result only in memory and loses it when the service restarts.

Nearby coordinates are sent to the configured live-aircraft provider. Map coordinates are sent to Google. A selected callsign may be sent to FlightAware, and a selected aircraft registration may be sent to Planespotters.net. Each provider's terms and privacy policy apply.

Flight Lane contains no analytics or advertising SDK. See [SECURITY.md](SECURITY.md) for key-handling guidance.

## License

The Flight Lane source is available under the [MIT License](LICENSE). Aircraft, map, route, and photo data remain subject to their providers' terms and licenses.
