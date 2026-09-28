#!/usr/bin/env bash
# One-time host preparation for running macOS and Windows under QEMU/KVM.
# Needs sudo. Debian/Ubuntu/Mint; adapt the package line for other distros.
set -euo pipefail

echo "==> Checking CPU virtualisation support"
grep -qE '^flags.*\b(vmx|svm)\b' /proc/cpuinfo \
  || { echo "ERROR: no VT-x/AMD-V. Enable virtualisation in firmware."; exit 1; }
grep -q '\bavx2\b' /proc/cpuinfo \
  || echo "WARNING: no AVX2 - macOS Ventura and later will not run."

echo "==> Installing QEMU and tooling"
sudo apt-get install -y qemu-system uml-utilities virt-manager git \
    wget libguestfs-tools p7zip-full make dmg2img tesseract-ocr \
    tesseract-ocr-eng genisoimage net-tools screen

echo "==> KVM tweaks for macOS guests"
# macOS reads MSRs KVM does not implement; without this it panics early.
sudo modprobe kvm
if grep -q GenuineIntel /proc/cpuinfo; then
  printf 'options kvm_intel nested=1\noptions kvm_intel emulate_invalid_guest_state=0\noptions kvm ignore_msrs=1 report_ignored_msrs=0\n' \
    | sudo tee /etc/modprobe.d/kvm.conf >/dev/null
else
  printf 'options kvm_amd nested=1\noptions kvm ignore_msrs=1 report_ignored_msrs=0\n' \
    | sudo tee /etc/modprobe.d/kvm.conf >/dev/null
fi
echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs >/dev/null

echo "==> Adding $(whoami) to kvm, libvirt, input"
sudo usermod -aG kvm,libvirt,input "$(whoami)"

cat <<MSG

Done. Verify:
  qemu-system-x86_64 --version                  # want >= 8.2.2
  cat /sys/module/kvm/parameters/ignore_msrs    # want Y

*** Log out and back in for the group changes to take effect, ***
*** then run ./install.sh ~/VMs                               ***
MSG
