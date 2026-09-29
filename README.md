# qemu-macos-vm-setup

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

Before first boot under these domains, check `EFI/OC/config.plist` on the
`OpenCore.qcow2` EFI partition (mount it with `mtools`/`guestmount`, or boot
once with OSX-KVM's own tooling and edit it there) for three things that
stock OpenCore configs often leave unset, and which cause macOS's USB stack
to silently never bind to QEMU's XHCI controller (see "Fixed" below for the
full symptom):

- `Kernel > Quirks > XhciPortLimit` → `true`
- `Kernel > Add` → `USBToolBox.kext` and `UTBMap.kext` both `Enabled`
- `DeviceProperties > Add` → a `built-in = 01` entry for the XHCI
  controller's own PCI path (`PciRoot(0x0)/Pci(0x2,0x1)/Pci(0x0,0x0)` for
  the topology these templates produce - confirm with `info qtree` in the
  QEMU monitor if you've changed the topology)

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

macOS has no inbox `virtio-net` driver, so its NIC is `vmxnet3` (macOS does
have a native driver for that one, `AppleVmxnet3Ethernet`, built in for
VMware Fusion compatibility) rather than virtio. Windows keeps `e1000e`
(see the Windows gotcha below) since it needs to boot with inbox drivers too.

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

**Fixed: keyboard, mouse and networking were all dead in macOS once booted**
(they worked fine at the OpenCore picker - UEFI-level input - then stopped
the moment macOS's own kernel drivers took over). Root cause: libvirt's
default q35 topology puts USB (`qemu-xhci`), video and network devices
behind auto-generated `pcie-root-port` bridges, and macOS's drivers silently
fail to engage with any device sitting behind one of those bridges - no
error, they just never bind (confirmed by grepping a verbose (`-v`) macOS
boot log for "usb"/"xhci"/"ethernet" and finding nothing, versus extensive
AHCI/APFS logging for everything that *did* work). It has nothing to do with
SPICE vs VNC, virt-manager vs `virt-viewer`, `usb-tablet` vs `usb-mouse`, or
NIC model (`e1000`, `e1000e` and `vmxnet3` all failed identically) - those
were all red herrings chased before the topology was identified as the
actual cause. Windows wasn't affected because its own bridged topology
happens not to trigger this particular driver failure.

The fix, already baked into `macos.xml.template`: no `<interface>` element,
and `<controller type='usb' model='none'/>` / `<video><model type='none'/>
</video>` stanzas, so libvirt doesn't auto-add its own bridged versions of
these devices. `<qemu:commandline>` then adds `qemu-xhci`, `VGA` and
`vmxnet3` back in "by hand", attached directly to `pcie.0` (explicit
`bus=pcie.0,addr=0x3/0x4/0x5`) instead of behind a root port - matching the
flat topology `run.sh` always used, which is why `run.sh` never had this
problem in the first place.

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
