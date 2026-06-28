#!/usr/bin/env bash
# bootstrap-fedora.sh
#
# Fresh Fedora FCC-unlock bootstrap for Fibocom L850-GL / Intel XMM7360.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" != "--yes-i-understand-regulatory-risk" ]]; then
  cat <<'EOF'
This script can persistently clear the L850-GL FCC lock by writing modem NVM.

Run only if you understand the regulatory/SAR risk and this is appropriate for
your own hardware and region.

To proceed:

  ./bootstrap-fedora.sh --yes-i-understand-regulatory-risk

EOF
  exit 2
fi

sudo "$DIR/prepare-usb-mode-fedora.sh"
sudo "$DIR/scripts/l850gl-fcc-unlock.py" --persistent --yes-i-understand-regulatory-risk
