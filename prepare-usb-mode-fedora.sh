#!/usr/bin/env bash
# prepare-usb-mode-fedora.sh
#
# Prepare Fibocom L850-GL / Intel XMM7360 in USB mode so the AT port is available.

set -euo pipefail

L850GL_USER="${L850GL_USER:-${SUDO_USER:-$(id -un)}}"
if [[ "$L850GL_USER" == "root" ]]; then
  L850GL_USER="$(logname 2>/dev/null || echo aidan)"
fi

L850GL_HOME="${L850GL_HOME:-$(getent passwd "$L850GL_USER" 2>/dev/null | cut -d: -f6)}"
L850GL_HOME="${L850GL_HOME:-/home/${L850GL_USER}}"

SRC_DIR="${SRC_DIR:-${L850GL_HOME}/src}"
ACPI_REPO="${ACPI_REPO:-https://github.com/mkottman/acpi_call.git}"
XMM_REPO="${XMM_REPO:-https://github.com/xmm7360/xmm7360-usb-modeswitch.git}"
ACPI_SRC="${ACPI_SRC:-${SRC_DIR}/acpi_call}"
XMM_SRC="${XMM_SRC:-${SRC_DIR}/xmm7360-usb-modeswitch}"
XMM2USB="${XMM2USB:-${XMM_SRC}/xmm2usb}"

log() {
  printf '[prepare-usb-mode] %s\n' "$*"
}

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

clone_or_update() {
  local url="$1"
  local dest="$2"

  if [[ -d "$dest/.git" ]]; then
    log "Updating existing repo: $dest"
    sudo -u "$L850GL_USER" git -C "$dest" pull --ff-only
  elif [[ -e "$dest" ]]; then
    echo "ERROR: $dest exists but is not a git repo"
    exit 1
  else
    log "Cloning $url -> $dest"
    sudo -u "$L850GL_USER" mkdir -p "$(dirname "$dest")"
    sudo -u "$L850GL_USER" git clone "$url" "$dest"
  fi
}

usb_present() {
  lsusb | grep -qi '2cb7:0007'
}

pci_present() {
  lspci -nn | grep -Eiq '8086:7360|XMM7360|Cellular controller/modem'
}

wait_for() {
  local label="$1"
  local timeout="$2"
  local cmd="$3"

  for ((i=1; i<=timeout; i++)); do
    if bash -lc "$cmd" >/dev/null 2>&1; then
      log "$label appeared after ${i}s"
      return 0
    fi
    sleep 1
  done

  echo "ERROR: timed out waiting for $label"
  return 1
}

log "Installing Fedora dependencies"
dnf install -y \
  git make gcc kernel-devel kernel-headers \
  usbutils pciutils \
  python3 python3-pyserial

log "Preparing source trees"
mkdir -p "$SRC_DIR"
chown "$L850GL_USER":"$L850GL_USER" "$SRC_DIR" 2>/dev/null || true
clone_or_update "$ACPI_REPO" "$ACPI_SRC"
clone_or_update "$XMM_REPO" "$XMM_SRC"

KVER="$(uname -r)"
if [[ ! -d "/lib/modules/${KVER}/build" ]]; then
  echo "ERROR: missing kernel build tree for running kernel: ${KVER}"
  echo "Try: sudo dnf install kernel-devel-${KVER}"
  exit 1
fi

log "Building/installing acpi_call for ${KVER}"
make -C "$ACPI_SRC" clean
make -C "$ACPI_SRC"

install -d -m 0755 "/lib/modules/${KVER}/extra"
install -m 0644 "${ACPI_SRC}/acpi_call.ko" "/lib/modules/${KVER}/extra/acpi_call.ko"
restorecon -v "/lib/modules/${KVER}/extra/acpi_call.ko" 2>/dev/null || true
depmod -a "$KVER"
modprobe acpi_call

if [[ ! -e /proc/acpi/call ]]; then
  echo "ERROR: /proc/acpi/call missing after modprobe acpi_call"
  exit 1
fi

if usb_present; then
  log "USB 2cb7:0007 already present"
else
  log "USB 2cb7:0007 not present; checking PCI 8086:7360"
  pci_present || {
    echo "ERROR: neither USB 2cb7:0007 nor PCI 8086:7360 is visible"
    exit 1
  }

  if [[ ! -x "$XMM2USB" ]]; then
    chmod +x "$XMM2USB" || true
  fi

  [[ -x "$XMM2USB" ]] || {
    echo "ERROR: xmm2usb missing or not executable: $XMM2USB"
    exit 1
  }

  grep -q '/proc/acpi/call' "$XMM2USB" || {
    echo "ERROR: xmm2usb does not appear to contain /proc/acpi/call guard"
    exit 1
  }

  log "Running xmm2usb once"
  "$XMM2USB"
  sleep 30
fi

wait_for "USB 2cb7:0007" 30 "lsusb | grep -qi '2cb7:0007'"
wait_for "/dev/ttyACM0" 30 "[[ -e /dev/ttyACM0 ]]"

log "USB mode ready"
lsusb | grep -Ei 'fibocom|2cb7|8087|07f5' || true
ls -l /dev/ttyACM* /dev/cdc-wdm* 2>/dev/null || true
