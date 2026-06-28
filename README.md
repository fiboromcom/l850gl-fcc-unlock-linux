# L850-GL FCC Unlock Linux

One-time FCC-lock clearing helper for Fibocom L850-GL / Intel XMM7360 modems.

This exists as a prerequisite repo for:

```text
https://github.com/fiboromcom/l850gl-enable-linux
```

## Why this exists

The L850-GL/XMM7360 can appear usable in Linux but refuse to enable the radio because of an FCC lock. The working boot-recovery repo assumes this has already been cleared once.

This repo performs that one-time preparation.

## Big warning

This writes modem NVM if you use the persistent mode.

Do not run this casually. You are responsible for regulatory/SAR implications and for deciding whether it is appropriate on your hardware and in your region.

The persistent command used here is based on the public `xmm7360-usb-modeswitch` notes:

```text
at@nvm:fix_cat_fcclock.fcclock_mode=0
at@store_nvm(fix_cat_fcclock)
```

## Supported target

Known target:

```text
ThinkPad X1 Carbon
Fibocom L850-GL
Intel XMM7360
USB ID after mode switch: 2cb7:0007
PCI ID before mode switch: 8086:7360
```

This is not a generic WWAN unlocker.

## Fresh Fedora usage

You need some temporary internet path first: Wi-Fi, Ethernet, or USB tethering.

```bash
sudo dnf install -y git
git clone https://github.com/fiboromcom/l850gl-fcc-unlock-linux.git
cd l850gl-fcc-unlock-linux
./bootstrap-fedora.sh --yes-i-understand-regulatory-risk
```

Running `./bootstrap-fedora.sh` without the confirmation flag prints the warning and exits without writing anything.

## Manual usage

Install dependencies and expose the modem in USB mode:

```bash
sudo ./prepare-usb-mode-fedora.sh
```

Check current FCC lock value:

```bash
sudo ./scripts/l850gl-fcc-unlock.py --check-only
```

Temporary unlock only, not stored:

```bash
sudo ./scripts/l850gl-fcc-unlock.py --yes-i-understand-regulatory-risk
```

Persistent unlock:

```bash
sudo ./scripts/l850gl-fcc-unlock.py --persistent --yes-i-understand-regulatory-risk
```

A marker file is written after persistent success:

```text
/etc/l850gl-fcc-unlock.done
```

The enable repo checks for that marker during bootstrap.

## Overrides

```bash
sudo L850GL_HOME="$HOME" \
  XMM2USB="$HOME/src/xmm7360-usb-modeswitch/xmm2usb" \
  ACPI_SRC="$HOME/src/acpi_call" \
  ./prepare-usb-mode-fedora.sh
```

```bash
sudo ./scripts/l850gl-fcc-unlock.py --port /dev/ttyACM0 --check-only
```

## Safety design

This repo does not install a boot service.

It is intended to be run once, before installing the boot-persistent enable repo.
