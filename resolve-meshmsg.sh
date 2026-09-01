#!/usr/bin/env bash
set -euo pipefail

candidates=(
  "$HOME/.local/bin/meshmsg"
  "$HOME/.cargo/bin/meshmsg"
)
if resolved="$(command -v meshmsg 2>/dev/null)"; then
  candidates+=("$resolved")
fi

seen=''
for candidate in "${candidates[@]}"; do
  [[ -x "$candidate" ]] || continue
  canonical="$(readlink -f "$candidate")"
  [[ ":$seen:" == *":$canonical:"* ]] && continue
  seen="${seen:+$seen:}$canonical"
  # v0.1.4 replaced seed/member command groups with equal-peer top-level
  # init, invite, and daemon commands. Reject older binaries that can read a
  # different state format even when they happen to provide `daemon`.
  help_output="$("$canonical" --help 2>&1 || true)"
  if grep -qE '^  daemon[[:space:]]' <<<"$help_output" \
    && grep -qE '^  init[[:space:]]' <<<"$help_output" \
    && grep -qE '^  invite[[:space:]]' <<<"$help_output"; then
    printf '%s\n' "$canonical"
    exit 0
  fi
done

echo "meshmsg v0.1.4 or newer was not found" >&2
exit 127
