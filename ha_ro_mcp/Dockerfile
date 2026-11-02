# Upstream: https://github.com/paulomac1000/ha-mcp-readonly
# Pinned by digest: bumping it is a deliberate update. Read upstream's diff
# since the last pinned tag first, then bump `version` in config.yaml with it.
FROM ghcr.io/paulomac1000/ha-mcp-readonly:v2.3.0@sha256:575dd60dc3a5bb7d1f0de47992d2c4a05b4ed1e36acdd957ab5077042755d669

# The image runs as uid 10001, which can read neither /data/options.json nor
# HA's .storage registries (0600). The config mount is read-only either way.
USER root
COPY --chmod=755 run.sh /run.sh
COPY shim.py /shim.py
ENTRYPOINT ["/run.sh"]
