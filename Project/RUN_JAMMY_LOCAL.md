# Run Jammy Server Locally on Windows (QEMU)

This guide runs your copied image:

- `C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.fresh.img`

## 1) Verify QEMU is installed

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" --version
```

## 2) Start the VM (WHPX acceleration, PMU enabled)

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" `
  -accel whpx `
  -cpu max,pmu=on `
  -m 4096 `
  -smp 2 `
  -drive file="C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.fresh.img",if=virtio,format=qcow2 `
  -netdev user,id=n1,hostfwd=tcp::2222-:22 `
  -device virtio-net-pci,netdev=n1 `
  -nographic
```

Notes:
- Keep this terminal open while VM runs.
- `hostfwd=tcp::2222-:22` means host port `2222` maps to guest SSH port `22`.
- `-cpu max,pmu=on` is required to expose hardware PMU counters (`cycles`, `instructions`, `branches`, `branch-misses`) to Linux `perf` in the guest.

## 3) SSH into the VM from another terminal

```powershell
ssh -p 2222 ubuntu@127.0.0.1
```

If your class image uses a different username, replace `ubuntu` accordingly.

## 4) Stop the VM

Inside VM (recommended):

```bash
sudo shutdown -h now
```

Or from the QEMU terminal: press `Ctrl+C`.

## 5) If WHPX fails, use TCG fallback (PMU enabled)

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" `
  -accel tcg `
  -cpu max,pmu=on `
  -m 4096 `
  -smp 2 `
  -drive file="C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.fresh.img",if=virtio,format=qcow2 `
  -netdev user,id=n1,hostfwd=tcp::2222-:22 `
  -device virtio-net-pci,netdev=n1 `
  -nographic
```

## 6) Verify PMU is exposed in the guest

After boot and SSH login, run:

```bash
ls /sys/bus/event_source/devices
perf stat -e cycles,instructions,branches,branch-misses -- sleep 1
```

Expected: no `<not supported>` lines for those four counters.

## 7) Optional: add QEMU to PATH (new terminals)

```powershell
setx PATH "$($env:PATH);C:\Program Files\qemu"
```

After this, open a new terminal and you can run:

```powershell
qemu-system-x86_64.exe --version
```

## PMU-Required Profiling Workflow

If your rubric requires hardware counters (`cycles`, `instructions`, `branches`, `branch-misses`), use a Linux host with KVM and PMU passthrough. Windows + WHPX on this machine exposes software events only in the guest.

Use:

- [Project/start_jammy_pmu_kvm.sh](Project/start_jammy_pmu_kvm.sh) to boot the VM on Linux host with `-cpu host,pmu=on`
- [subRay/scripts/run_pmu_profiles_linux.sh](subRay/scripts/run_pmu_profiles_linux.sh) to run non-fast profiles for Attempts 1/2/3

Minimal verification in guest:

```bash
ls /sys/bus/event_source/devices
perf stat -e cycles,instructions,branches,branch-misses -- sleep 1
```

Expected: no `<not supported>` for those four counters.
