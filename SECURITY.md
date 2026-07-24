# Security

## Provider credentials

Store provider keys only in `.env.local`. That file is ignored by Git. The build writes only the local service URL to `source/config.generated.brs`, and that generated file is ignored as well.

Before sharing a ZIP or commit, run:

```powershell
npm run check
git status --short
```

The validation task inspects the Roku package for provider hostnames, header names, and environment-variable markers that belong only on the local computer.

Restrict each provider key to the smallest set of APIs possible and enable usage alerts. Rotate a key immediately if it is committed, pasted into an issue, included in a screenshot, or otherwise disclosed.

## Local network boundary

The service defaults to `LOCAL_NETWORK_ONLY=true` and rejects source addresses outside private or loopback ranges. This is a safety boundary, not user authentication.

- Do not configure router port forwarding for the service.
- Do not place the service on a public host.
- Allow Node.js through the host firewall only for Private networks.
- Avoid running it on an untrusted shared network.
- Keep the computer and Node.js dependencies updated.

## Roku developer password

The deployment script prompts for the Roku developer password using a secure PowerShell prompt. It never reads the password from `.env.local` or saves it. Do not add a password variable to the environment file.

## Reporting a vulnerability

Open a GitHub security advisory for the repository instead of a public issue. Do not include active API keys, a full home address, coordinates, or a Roku developer password in the report.
