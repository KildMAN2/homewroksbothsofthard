#!/usr/bin/env bash
set -euo pipefail

# Run this on a Linux host with /dev/kvm available.
# Update IMG_PATH to your local image location.
IMG_PATH="${IMG_PATH:-$HOME/homewroksbothsofthard/Project/jammy-server-cloudimg-amd64-disk-kvm.fresh.img}"
SSH_PORT="${SSH_PORT:-2222}"

if [[ ! -e /dev/kvm ]]; then
  echo "ERROR: /dev/kvm is missing. PMU passthrough requires KVM on Linux host." >&2
  exit 1
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "ERROR: image not found: $IMG_PATH" >&2
  exit 1
fi

exec qemu-system-x86_64 \
  -enable-kvm \
  -cpu host,pmu=on \
  -m 4096 \
  -smp 2 \
  -drive file="$IMG_PATH",if=virtio,format=qcow2 \
  -netdev user,id=n1,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-pci,netdev=n1 \
  -nographic
