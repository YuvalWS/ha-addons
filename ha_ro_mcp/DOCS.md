# HA RO MCP

Wraps [paulomac1000/ha-mcp-readonly](https://github.com/paulomac1000/ha-mcp-readonly) as an
add-on, so an AI agent (Claude Code) can read entities and states, render templates and read the
core and add-on logs, and nothing else.

This file owns the add-on. How it is reached from outside - the Cloudflare host, Access, the
client and the full setup order - is owned by `docs/network.md` ("The RO MCP host") in
[Home-Assistant-Config](https://github.com/YuvalWS/Home-Assistant-Config); start there.

## Security model - read before changing anything

- **Home Assistant enforces nothing here.** The add-on talks to HA through the Supervisor with an
  admin-level token (`homeassistant_api`, plus `hassio_api` with the `homeassistant` role for the
  core log). It is read-only for two reasons: upstream's code makes nothing but `GET` requests
  plus `POST /api/template` (templates cannot call services) - checked by reading its source at
  `v2.3.0` - and every request passes through `shim.py`, which refuses anything else. The shim
  runs in the same container, so it guards against an upstream bug, not a malicious image.
- **So the image is pinned by digest** in the `Dockerfile`. An update is a deliberate act: read
  upstream's diff since the pinned tag (look for any new `method="POST"`, a WebSocket client, or a
  write to the filesystem), then bump the digest and `version` in `config.yaml` together.
- **It runs as root inside its container**, because HA's `.storage` registries are `0600`. The
  config folder is mounted read-only (`/homeassistant`); upstream refuses to read `secrets.yaml`,
  `.storage/auth*` and `onboarding` itself.
- **No host ports.** The MCP endpoint (`:9092/mcp`) is reachable only on the Supervisor's internal
  network, by the cloudflared add-on. Every request needs `Authorization: Bearer <mcp_auth_token>`
  and a `Host` header equal to `public_hostname`. The health endpoint (`:9091`) is unauthenticated
  but internal only.

## Install

1. Add this repository (see the [README](../README.md)) and install **HA RO MCP**.
2. **Configuration:**
   - `public_hostname` - the hostname the tunnel publishes, e.g. `ha-ro-mcp.yuweiss.uk`.
   - `mcp_auth_token` - at least 32 random characters. Generate one with
     `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` and keep it in your
     password manager; the client sends the same value (the cloud environment's network secret,
     step 6 of the setup in `docs/network.md`).
3. **Start** it and check the **Log** tab: `HA API check: HTTP 200`, then the server listening on
   `0.0.0.0:9092`. Any other check result means the tools will report "Home Assistant backend is
   unavailable" - the server probes HA once at start and switches its HA tools off if that fails;
   restart the add-on once the cause is fixed. Requests the shim or the Supervisor refuse are
   logged with their status.
4. The **Info** tab shows the add-on's **Hostname** (`<hash>-ha-ro-mcp`). The tunnel route
   points at `http://<that hostname>:9092`.

## Resources

A Python process, idle until called. Every tool call is one or a few REST calls to HA; templates
and history queries run on the Pi, so keep history windows short.
