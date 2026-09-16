& "C:\Program Files\qemu\qemu-system-x86_64.exe" `
  -accel whpx `
  -m 4096 `
  -smp 2 `
  -drive file="C:\Users\Sarim\homewroksbothsofthard\Project\jammy-server-cloudimg-amd64-disk-kvm.fresh.img",if=virtio,format=qcow2 `
  -netdev user,id=n1,hostfwd=tcp::2222-:22 `
  -device virtio-net-pci,netdev=n1 `
  -nographic
