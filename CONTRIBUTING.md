# Contributing

Contributions that improve privacy, local setup, provider efficiency, Roku compatibility, accessibility, or flight-display accuracy are welcome.

## Development

1. Fork and clone the repository.
2. Run `npm install`.
3. Run `npm run setup` and add your own provider settings to `.env.local`.
4. Make focused changes.
5. Run `npm run check`.
6. Confirm no generated package, environment file, address, coordinate, device address, password, or provider key is staged.

Keep provider requests in `server/server.mjs`. Provider credentials and provider URLs must not be added to BrightScript or the generated Roku ZIP.

Use Node's built-in test runner for local service tests. BrightScript is checked with BrighterScript.

When reporting a UI issue, share a redacted debug log and avoid screenshots that reveal a private residence or exact map location.
