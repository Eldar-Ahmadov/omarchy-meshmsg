#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
meshmsg_bin="$($script_dir/resolve-meshmsg.sh)"

exec "$meshmsg_bin" --json daemon
