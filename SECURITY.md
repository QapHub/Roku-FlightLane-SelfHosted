# Security

## Provider data

By default Flight Lane uses only free providers that need no keys. The one optional credential is `FLIGHTAWARE_API_KEY`, which is billed per query: keep it only in `.env.local` (ignored by Git), never paste it into issues or screenshots, and rotate it in the AeroAPI portal if it is disclosed. Keep `.env.local` out of Git in any case; it also holds your network addresses. The build writes only the local service URL to `source/config.generated.brs`, and that generated file is ignored as well.

Before sharing a ZIP or commit, run:

```sh
npm run check
git status --short
```

The validation task inspects the Roku package for provider hostnames that belong only on the local computer, so the Roku always talks to your local service rather than to providers directly.

## Local network boundary

The service defaults to `LOCAL_NETWORK_ONLY=true` and rejects source addresses outside private or loopback ranges. This is a safety boundary, not user authentication.

- Do not configure router port forwarding for the service.
- Do not place the service on a public host.
- Allow Node.js through the host firewall only for Private networks.
- Avoid running it on an untrusted shared network.
- Keep the computer and Node.js dependencies updated.

## Roku developer password

The deployment script prompts for the Roku developer password without echoing it to the terminal and passes it to `curl` on standard input, so it never appears in the process list. It never reads the password from `.env.local` or saves it. Do not add a password variable to the environment file.

## Reporting a vulnerability

Open a GitHub security advisory for the repository instead of a public issue. Do not include active API keys, a full home address, coordinates, or a Roku developer password in the report.
