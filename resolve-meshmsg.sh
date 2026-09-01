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
  # The plugin requires the daemon-based meshmsg interface (0.1.1+).
  if "$canonical" --help 2>&1 | grep -qE '^  daemon[[:space:]]'; then
    printf '%s\n' "$canonical"
    exit 0
  fi
done

echo "A daemon-capable meshmsg binary was not found" >&2
exit 127
