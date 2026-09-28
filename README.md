# qemu-vm-setup

Working libvirt/QEMU definitions for running **macOS Sonoma** and **Windows 11**
as desktop VMs on a Linux host, managed together in virt-manager.

Built on a **13th Gen Intel Core i5-1345U** (a hybrid P-core/E-core CPU) running
Linux Mint 22.3 / Ubuntu 24.04, QEMU 8.2.2. The hybrid CPU detail matters more
than it sounds — see [docs/hybrid-cpu.md](docs/hybrid-cpu.md).

This replaced a VirtualBox setup. If you are coming from VirtualBox too, read
[docs/migrating-from-virtualbox.md](docs/migrating-from-virtualbox.md) first.

## Why not VirtualBox

- `myspaghetti/macos-virtualbox`, the usual macOS-on-VirtualBox installer, was
  **archived in August 2023** and only ever supported High Sierra, Mojave and
  Catalina. VirtualBox's EFI cannot boot Big Sur or later, so Catalina (2019) is
  the hard ceiling on that path.
- On a hybrid-CPU host, VirtualBox exposes the real host CPUID to the guest and
  macOS hangs during secondary-CPU startup. The only workaround is a single
  vCPU. QEMU sidesteps this by handing the guest an explicit CPU model.
- VirtualBox and KVM both want VT-x. Sharing was only fixed in VirtualBox 7.2.0+
  **on kernel >= 6.16**. Below that you cannot run a VirtualBox VM and a
  QEMU/KVM VM at the same time.

## Layout

    macos-sonoma/
      macos.xml.template    libvirt domain
      run.sh.template       direct-QEMU launcher, for debugging without libvirt
    win11/
      win11.xml.template    libvirt domain
    docs/
      hybrid-cpu.md                 the macOS-hangs-on-hybrid-CPU problem
      migrating-from-virtualbox.md  converting an existing VirtualBox VM
      snap-environment.md           QEMU dying when launched from a snap terminal
    host-setup.sh           one-time host preparation (needs sudo)
    install.sh              fills in your paths and defines the domains

Disk images are **not** in this repo — see `.gitignore`. You supply those.

## Setup

    ./host-setup.sh          # packages, KVM tweaks, group membership. Log out and back in.
    ./install.sh ~/VMs       # writes real paths into the templates and defines the domains

`install.sh` expects your images to be laid out as:

    ~/VMs/macos-sonoma/   macos.qcow2  OpenCore.qcow2  OVMF_CODE.fd  OVMF_VARS.fd
    ~/VMs/win11/          win11.qcow2  OVMF_VARS.fd    virtio-win.iso

### Getting the macOS images

Use [kholia/OSX-KVM](https://github.com/kholia/OSX-KVM), which is actively
maintained and supports up to macOS 26 Tahoe:

    git clone --depth 1 https://github.com/kholia/OSX-KVM.git && cd OSX-KVM
    ./fetch-macOS-v2.py --shortname sonoma    # --shortname makes it non-interactive
    dmg2img -i BaseSystem.dmg -o BaseSystem.img
    qemu-img create -f qcow2 macos.qcow2 128G

Install with OSX-KVM's `OpenCore-Boot.sh` (attach `BaseSystem.img`), then move
`macos.qcow2`, `OpenCore.qcow2` and the OVMF files here and use these domains
instead. Detach `BaseSystem.img` once installed.

## Day to day

    virt-manager                                    # both VMs in one list
    virsh -c qemu:///session list --all
    virsh -c qemu:///session start macos-sonoma
    virsh -c qemu:///session shutdown win11

After editing an XML, re-apply it:

    virsh -c qemu:///session define macos-sonoma/macos.xml

## Session mode, not system mode

These domains are defined on **`qemu:///session`**, not the usual
`qemu:///system`. Session mode runs QEMU as your own user, so:

- no `sudo` is needed anywhere after `host-setup.sh`
- VM images under `$HOME` just work

Under system mode QEMU runs as `libvirt-qemu`, which cannot traverse a
`drwxr-x---` home directory — you would need `setfacl -m u:libvirt-qemu:rx` on
your home and VM directory. The tradeoff is that session mode only offers
user-mode (NAT) networking, with no bridging. Both VMs here use NAT, so it costs
nothing.

virt-manager defaults to the system connection, so `install.sh` points it at the
session one and installs a launcher that passes `--connect qemu:///session`
explicitly. Relying on the `autoconnect` gsetting alone proved unreliable — it
would open showing **"QEMU/KVM User session - Not Connected"** and an empty list.
If you ever see that, double-click the row to connect.

## Gotchas

**macOS will not boot without `isa-applesmc`.** It is passed through
`<qemu:commandline>` in the domain XML, along with the `-cpu` line, because
`kvm=on` and `vmware-cpuid-freq=on` cannot be expressed in libvirt's `<cpu>`
element. Do not "tidy" those into a normal `<cpu mode='host-passthrough'>` — on a
hybrid host that reintroduces the hang described in
[docs/hybrid-cpu.md](docs/hybrid-cpu.md).

**At the OpenCore picker, choose `MacHD`**, not `EFI`.

**Windows uses SATA and e1000e here, deliberately.** Those match what a migrated
VirtualBox VM already has drivers for. To get virtio speed, install the drivers
from `virtio-win.iso` *inside Windows first*, then switch the disk and NIC over.
Switching first gives `INACCESSIBLE_BOOT_DEVICE`.

**The macOS installer's phase-1 progress bar lies.** It can sit on the same
"About 2 hours remaining" for 20+ minutes while working perfectly. Judge progress
by disk growth, not the UI:

    watch -n5 'ls -l ~/VMs/macos-sonoma/macos.qcow2'

**macOS Big Sur and later can sit for a long time on Setup Assistant screens**,
particularly Country Selection. Let it.

## Memory

Both domains are set to 8 GB, chosen so they can run simultaneously on a 30 GB
host. Adjust in virt-manager to taste.

## Licence

MIT. The OpenCore images and OVMF firmware come from their own projects under
their own licences.
