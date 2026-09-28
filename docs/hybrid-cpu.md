# macOS hangs on hybrid P-core/E-core CPUs

## Symptom

macOS begins booting, the Apple logo and progress bar appear, and then it stops
forever. No panic, no error. Under VirtualBox this happens every time on a
12th-gen-or-later Intel laptop CPU.

## Diagnosis

Take the guest CPU state at power-off. Under VirtualBox that is in `VBox.log`;
under QEMU use `info registers` on the monitor. The tell is that the two vCPUs
are in different modes:

| | VCPU 0 (boot processor) | VCPU 1 (secondary) |
|---|---|---|
| Paging mode | `AMD64+NX` | **`Protected`** |
| `cr0` | `c0010033` (PG=1) | **`40010033` (PG=0)** |
| `EFER` | `0d00` (LME+LMA set) | **`0800` (LME clear)** |
| instruction pointer | kernel space | low memory |

VCPU 0 is running the 64-bit kernel normally. VCPU 1 never left the 32-bit
**application-processor startup trampoline** — it never entered long mode. The
kernel booted, then blocked in `cpu_start` waiting for an acknowledgement that
never came.

## Cause

Hybrid CPUs — Alder Lake, Raptor Lake and later — mix P-cores and E-cores with
different feature sets and different maximum frequencies, and advertise this via
the hybrid bit (`CPUID.07H:EDX[15]`) and CPUID leaf `0x1A`.

XNU has no concept of heterogeneous cores. Given the real host CPUID it
mishandles AP bring-up and hangs. This is a host-hardware incompatibility, not a
configuration mistake.

Confirm a hybrid host with:

    lscpu -e=CPU,CORE,MAXMHZ      # two distinct MAXMHZ groups
    ls /sys/devices/cpu_core /sys/devices/cpu_atom    # both exist => hybrid

## Fix under QEMU (what this repo does)

Hand the guest an explicit CPU model so it never sees the host CPUID:

    -cpu Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,...

`-hle,-rtm` mask TSX, which is disabled in microcode on these parts anyway and
which macOS dislikes. With this you can run 4 vCPUs normally.

Because `kvm=on` and `vmware-cpuid-freq=on` have no libvirt `<cpu>` equivalent,
this has to go through `<qemu:commandline>`. That is why the domain XML looks
unusual, and why replacing it with `<cpu mode='host-passthrough'/>` reintroduces
the hang.

If a given macOS release misbehaves with `Skylake-Client`, `Haswell-noTSX` is the
other model commonly used; OSX-KVM's own script suggests it for Sonoma, though
`Skylake-Client` works fine in practice.

## Workarounds under VirtualBox, for reference

VirtualBox cannot mask this cleanly. The options are:

    VBoxManage modifyvm <vm> --cpus 1                          # no AP to hang
    VBoxManage modifyvm <vm> --cpu-profile "Intel Core i7-6700K"
    VBoxManage modifyvm <vm> --cpuid-remove 0000001a

Single-vCPU is the only reliable one, and it costs all parallelism. This is a
large part of why this setup moved to QEMU.
