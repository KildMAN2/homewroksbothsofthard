# Run Jammy Server Locally on Windows (QEMU)

This guide runs your copied image:

- `C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.img`

## 1) Verify QEMU is installed

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" --version
```

## 2) Start the VM (WHPX acceleration)

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" `
  -accel whpx `
  -m 4096 `
  -smp 2 `
  -drive file="C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.img",if=virtio,format=qcow2 `
  -netdev user,id=n1,hostfwd=tcp::2222-:22 `
  -device virtio-net-pci,netdev=n1 `
  -nographic
```

Notes:
- Keep this terminal open while VM runs.
- `hostfwd=tcp::2222-:22` means host port `2222` maps to guest SSH port `22`.

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

## 5) If WHPX fails, use TCG fallback

```powershell
& "C:\Program Files\qemu\qemu-system-x86_64.exe" `
  -accel tcg `
  -m 4096 `
  -smp 2 `
  -drive file="C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.img",if=virtio,format=qcow2 `
  -netdev user,id=n1,hostfwd=tcp::2222-:22 `
  -device virtio-net-pci,netdev=n1 `
  -nographic
```

## 6) Optional: add QEMU to PATH (new terminals)

```powershell
setx PATH "$($env:PATH);C:\Program Files\qemu"
```

After this, open a new terminal and you can run:

```powershell
qemu-system-x86_64.exe --version
```
