#!/bin/sh
# Maps the add-on options onto the environment the upstream server reads.
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

# Upstream's cleartext-HTTP guard resolves a hostname to its IP and drops the
# URL path, which would turn http://supervisor/core into the Supervisor's own
# API. A literal private IP is passed through unchanged, so resolve it here.
SUPERVISOR_IP=$(getent hosts supervisor | cut -d' ' -f1)

export HA_URL="http://${SUPERVISOR_IP}/core"
export HA_TOKEN="$SUPERVISOR_TOKEN"
export HA_CONFIG_PATH=/homeassistant
export MCP_TRANSPORT=http
export MCP_BIND_HOST=0.0.0.0
export MCP_AUTH_TOKEN
export MCP_ALLOWED_HOSTS="${PUBLIC_HOSTNAME},localhost,127.0.0.1"
# Template rendering lives in the dev tools.
export MCP_DEV_TOOLS_ENABLED=1

exec ha-mcp-readonly
