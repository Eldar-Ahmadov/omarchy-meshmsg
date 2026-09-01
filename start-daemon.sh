#!/usr/bin/env bash
set -euo pipefail

meshmsg_bin="${1:-}"
if [[ -z "$meshmsg_bin" ]]; then
  meshmsg_bin="$(command -v meshmsg || true)"
fi
if [[ -z "$meshmsg_bin" || ! -x "$meshmsg_bin" ]]; then
  echo "meshmsg is not installed or not executable" >&2
  exit 127
fi

# Respect a user-managed persistent unit when one exists. Replace only a
# transient unit previously created by this helper, which may reference an old
# meshmsg binary after an upgrade.
if [[ "$(systemctl --user show meshmsg.service -p Transient --value 2>/dev/null || true)" == "yes" ]]; then
  systemctl --user stop meshmsg.service >/dev/null 2>&1 || true
  systemctl --user reset-failed meshmsg.service >/dev/null 2>&1 || true
  for _ in {1..20}; do
    [[ "$(systemctl --user show meshmsg.service -p LoadState --value 2>/dev/null || true)" == "not-found" ]] && break
    sleep 0.1
  done
fi

if systemctl --user cat meshmsg.service >/dev/null 2>&1; then
  systemctl --user start meshmsg.service
else
  systemd-run --user --quiet --unit=meshmsg --collect \
    --property=Description='meshmsg peer daemon' \
    --property=Restart=on-failure \
    --property=RestartSec=5 \
    "$meshmsg_bin" --json daemon
fi
