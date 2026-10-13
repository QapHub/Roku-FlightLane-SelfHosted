# Roku setup and sideloading

## 1. Enable developer mode

The computer and Roku must be connected to the same normal home network. Guest Wi-Fi commonly blocks device-to-device traffic.

Using the Roku remote, press:

```text
Home, Home, Home, Up, Up, Right, Left, Right, Left, Right
```

Write down the Roku URL shown on screen, enable the Development Application Installer, accept the developer agreement, and create a case-sensitive developer password. The Roku restarts.

Roku's official instructions are at [Activating developer mode](https://developer.roku.com/dev/docs/developer-setup).

## 2. Find the computer's private-network address

Run:

```sh
npm run setup
```

The script lists likely IPv4 addresses. You can also run:

```sh
# macOS (Wi-Fi is usually en0; Ethernet may be en1 or another enN)
ipconfig getifaddr en0

# Windows
ipconfig
```

Use the IPv4 address for the adapter connected to the same network as the Roku. It commonly begins with `192.168.`, `10.`, or `172.16.` through `172.31.`.

Set these values in `.env.local`:

```dotenv
FLIGHTLANE_API_URL=http://COMPUTER_IP:8787
ROKU_DEVICE_IP=ROKU_IP
```

Reserve the computer and Roku addresses in your router's DHCP settings if possible. Otherwise, an address change will require rebuilding and reinstalling the Roku app.

## 3. Start the local service

```sh
npm run api
```

On first launch, the firewall may ask whether Node.js can accept incoming connections:

- **macOS:** select **Allow** when asked whether `node` may accept incoming network connections. If you dismissed the prompt, open **System Settings > Network > Firewall > Options** and set `node` to allow incoming connections. macOS may also ask for **Local Network** access for your terminal app; allow it so the deploy and debug helpers can reach the Roku (**System Settings > Privacy & Security > Local Network**).
- **Windows:** allow Node.js on **Private networks** only.

Leave the terminal open whenever Flight Lane is in use. To keep a Mac from sleeping while the service runs, start it with `caffeinate -i npm run api`.

Verify it locally:

```sh
curl http://localhost:8787/health
```

The health response reports which optional features are enabled.

## 4. Install Flight Lane

The automated installer builds the ZIP, asks for the developer password, and uploads it:

```sh
npm run deploy
```

The password is not written to `.env.local`, the repository, or a log.

### Manual installation

If the script cannot reach the Roku:

1. Run `npm run build`.
2. Open `http://ROKU_IP` in a browser.
3. Sign in as `rokudev` using the developer password.
4. Upload `dist/flight-lane.zip`.
5. Select **Install**.

The app should launch immediately and appear as a development app on the Roku home screen.

## 5. Configure the app

On first launch, enter the location to monitor. Use the `*` button later to:

- change the address;
- select a radius from 1 through 10 miles;
- choose the idle display timeout;
- show or hide the 24-hour flyover count in the header. Its default comes from `SHOW_FLYOVER_COUNT` in `.env.local` (on unless set to `false`); a choice made in settings is saved on the Roku and takes precedence.

The live list and map show only aircraft inside the selected radar radius. The PIP follows the selected aircraft; choosing a plane manually keeps that selection until it disappears from the area.

## Screensaver package

Build the standalone package with:

```sh
npm run build:screensaver
```

Upload `dist/flight-lane-screensaver.zip` through the Roku Development Application Installer, then select Flight Lane in the Roku screensaver settings.

Roku permits only one sideloaded development app, so installing the screensaver package replaces the sideloaded main app. This does not affect apps installed from the Streaming Store.

## Updating

Pull the latest code, install dependencies if the lockfile changed, restart the local service, and deploy again:

```sh
git pull
npm install
npm run deploy
```

If Roku reports that the identical version is already installed, remove the development app first or increment `build_version` in `manifest`.
