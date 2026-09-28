# Migrating a VirtualBox VM to QEMU/KVM

Worked example: a Windows 11 guest, 80 GB virtual / 37 GB actual.

## 1. Check BitLocker first

If the guest is Windows with BitLocker enabled **and** backed by a TPM, changing
the TPM locks you out at boot. Before touching anything, inside Windows:

    manage-bde -status

If it is on, suspend it or save the recovery key.

Check whether the source VM even has a TPM:

    grep -iE "tpm|secureboot" "~/VirtualBox VMs/<vm>/<vm>.vbox"

No match means Windows 11 was installed with the TPM/Secure Boot requirement
bypassed — BitLocker cannot be TPM-backed, and this risk does not apply.

## 2. Record the source hardware

    VBoxManage showvminfo "<vm>" --machinereadable | \
      grep -E "^(firmware|chipset|cpus|memory|nictype1|storagecontrollertype0)="

Match these in the new domain for the first boot. Modernising the virtual
hardware and migrating at the same time turns one problem into two.

The example VM reported `firmware="EFI"`, `chipset="piix3"`,
`storagecontrollertype0="IntelAhci"`, `nictype1="82540EM"` — so: UEFI without
Secure Boot, SATA/AHCI disk, e1000-family NIC. All have inbox Windows drivers.

## 3. Convert the disk

VM shut down, VirtualBox closed:

    qemu-img convert -p -f vdi -O qcow2 \
      "~/VirtualBox VMs/<vm>/<vm>.vdi" ~/VMs/<vm>/<vm>.qcow2

Then verify before trusting it:

    qemu-img check ~/VMs/<vm>/<vm>.qcow2      # expect "No errors were found"

This is a read-only copy. The original `.vdi` is untouched — keep it as a
rollback until you are satisfied.

## 4. Give it its own UEFI variable store

    cp /usr/share/OVMF/OVMF_VARS_4M.fd ~/VMs/<vm>/OVMF_VARS.fd
    chmod u+w ~/VMs/<vm>/OVMF_VARS.fd

Use `OVMF_VARS_4M.ms.fd` and `OVMF_CODE_4M.secboot.fd` instead **only** if the
source VM actually used Secure Boot.

## 5. Boot it

The new NVRAM has no boot entries, so UEFI has to find the bootloader itself.
OVMF's auto-discovery usually manages it — you should see:

    BdsDxe: loading Boot0001 "UEFI QEMU HARDDISK ..."

If instead you land at a UEFI shell, point it at the bootloader by hand:

    FS0:\EFI\Microsoft\Boot\bootmgfw.efi

Windows rewrites its own boot entry afterwards, so this is needed once.

## 6. Expect a slow first boot

Windows shows **"Getting devices ready"** while it detects the new virtual
hardware, and may reboot once or twice. This is normal and can take several
minutes. Pending Windows Updates often install at the same time.

Reactivation may trigger from the hardware change; a digital licence tied to a
Microsoft account normally reactivates itself.

## 7. Only then modernise

Once it boots reliably, install the virtio drivers from
[virtio-win](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
*inside Windows*, and only after that switch the disk and NIC to virtio in
virt-manager. Doing it the other way round gives `INACCESSIBLE_BOOT_DEVICE`.

## Note on running both hypervisors

VirtualBox and KVM both need VT-x. VirtualBox 7.2.0+ can share it through KVM's
APIs, but only on **kernel >= 6.16**. Below that, a VirtualBox VM and a QEMU/KVM
VM cannot run simultaneously — sequentially is fine. Check with `uname -r` and
`VBoxManage --version`.
