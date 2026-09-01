#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
unit_name="meshmsg.service"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit_path="$unit_dir/$unit_name"
owner_marker="$unit_dir/.meshmsg-service-installed-by-eldar-meshmsg"
source_unit="$script_dir/meshmsg.service"

# A previous plugin release used systemd-run. Remove only that transient unit;
# never overwrite a persistent unit managed by the user.
if [[ "$(systemctl --user show "$unit_name" -p Transient --value 2>/dev/null || true)" == "yes" ]]; then
  systemctl --user stop "$unit_name" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit_name" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    [[ "$(systemctl --user show "$unit_name" -p LoadState --value 2>/dev/null || true)" == "not-found" ]] && break
    sleep 0.1
  done
fi

fragment="$(systemctl --user show "$unit_name" -p FragmentPath --value 2>/dev/null || true)"
if [[ -z "$fragment" ]]; then
  mkdir -p "$unit_dir"
  install -m 0644 "$source_unit" "$unit_path"
  touch "$owner_marker"
  systemctl --user daemon-reload
elif [[ "$fragment" == "$unit_path" && -f "$owner_marker" ]] && ! cmp -s "$source_unit" "$unit_path"; then
  # Update only a unit this plugin previously installed. A pre-existing unit
  # at the conventional path has no ownership marker and remains untouched.
  install -m 0644 "$source_unit" "$unit_path"
  systemctl --user daemon-reload
fi

# Enable, rather than merely start, so the daemon returns after reboot/login.
systemctl --user enable --now "$unit_name"
