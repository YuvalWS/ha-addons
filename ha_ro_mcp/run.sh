#!/bin/sh
# Maps the add-on options onto the environment the upstream server reads, and
# puts shim.py between the server and the Supervisor (why: shim.py's header).
set -eu

opt() {
    python3 -c 'import json, sys; print(json.load(open("/data/options.json")).get(sys.argv[1]) or "")' "$1"
}

PUBLIC_HOSTNAME=$(opt public_hostname)
MCP_AUTH_TOKEN=$(opt mcp_auth_token)

if [ "${#MCP_AUTH_TOKEN}" -lt 32 ]; then
    echo "mcp_auth_token must be at least 32 characters" >&2
    exit 1
fi
if [ -z "$PUBLIC_HOSTNAME" ]; then
    echo "public_hostname is required (the hostname the tunnel publishes)" >&2
    exit 1
fi

LOCAL_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
LOCAL_TOKEN="$LOCAL_TOKEN" python3 /shim.py &

# Startup check, so the log says whether HA answers before any tool is called.
LOCAL_TOKEN="$LOCAL_TOKEN" python3 - <<'PY'
import os, time, urllib.error, urllib.request
request = urllib.request.Request(
    "http://127.0.0.1:8099/api/", headers={"Authorization": f"Bearer {os.environ['LOCAL_TOKEN']}"}
)
for attempt in range(20):
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            print(f"HA API check: HTTP {response.status}", flush=True)
            break
    except urllib.error.HTTPError as err:
        print(f"HA API check: HTTP {err.code} {err.read()[:200]!r}", flush=True)
        break
    except OSError:
        time.sleep(0.5)
else:
    print("HA API check: shim did not start", flush=True)
PY

export HA_URL=http://127.0.0.1:8099
export HA_TOKEN="$LOCAL_TOKEN"
export HA_CONFIG_PATH=/homeassistant
export MCP_TRANSPORT=http
export MCP_BIND_HOST=0.0.0.0
export MCP_AUTH_TOKEN
export MCP_ALLOWED_HOSTS="${PUBLIC_HOSTNAME},localhost,127.0.0.1"
# Template rendering lives in the dev tools.
export MCP_DEV_TOOLS_ENABLED=1

exec env -u SUPERVISOR_TOKEN ha-mcp-readonly
