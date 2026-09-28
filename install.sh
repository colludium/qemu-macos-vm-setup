#!/usr/bin/env bash
# Fill real paths into the templates and define the domains on qemu:///session.
# Safe to re-run; re-defining an existing domain just updates it.
set -euo pipefail

VM_ROOT="${1:-$HOME/VMs}"
VM_ROOT="${VM_ROOT%/}"
REPO="$(cd "$(dirname "$0")" && pwd)"
CONN="qemu:///session"

[ -d "$VM_ROOT" ] || { echo "ERROR: $VM_ROOT does not exist."; exit 1; }
command -v virsh >/dev/null || { echo "ERROR: virsh missing. Run ./host-setup.sh first."; exit 1; }
id -nG | grep -qw kvm || echo "WARNING: not in the 'kvm' group yet - did you log out and back in?"

render() {  # render <template> <output>
  sed -e "s|__VM_ROOT__|$VM_ROOT|g" -e "s|__HOME__|$HOME|g" "$1" > "$2"
}

echo "==> Rendering configs for VM_ROOT=$VM_ROOT"
render "$REPO/macos-sonoma/macos.xml.template" "$REPO/macos-sonoma/macos.xml"
render "$REPO/win11/win11.xml.template"        "$REPO/win11/win11.xml"
render "$REPO/macos-sonoma/run.sh.template"    "$REPO/macos-sonoma/run.sh"
chmod +x "$REPO/macos-sonoma/run.sh"

echo "==> Checking for required images"
missing=0
for f in "$VM_ROOT/macos-sonoma/macos.qcow2" "$VM_ROOT/macos-sonoma/OpenCore.qcow2" \
         "$VM_ROOT/macos-sonoma/OVMF_CODE.fd" "$VM_ROOT/macos-sonoma/OVMF_VARS.fd" \
         "$VM_ROOT/win11/win11.qcow2" "$VM_ROOT/win11/OVMF_VARS.fd" \
         "$VM_ROOT/win11/virtio-win.iso"; do
  [ -e "$f" ] || { echo "   missing: $f"; missing=1; }
done
[ "$missing" -eq 1 ] && echo "   (domains referencing missing files will fail to start)"

# Re-defining a domain that already exists fails unless the XML carries its
# existing UUID, so reuse it when there is one. Makes this safely re-runnable.
define_domain() {
  local xml="$1" name uuid
  name=$(sed -n 's|.*<name>\(.*\)</name>.*|\1|p' "$xml" | head -1)
  uuid=$(virsh -c "$CONN" domuuid "$name" 2>/dev/null | tr -d '[:space:]' || true)
  if [ -n "$uuid" ] && ! grep -q "<uuid>" "$xml"; then
    sed -i "s|<name>$name</name>|<name>$name</name><uuid>$uuid</uuid>|" "$xml"
    echo "   reusing existing uuid for $name"
  fi
  virt-xml-validate "$xml" >/dev/null || { echo "   INVALID: $xml"; return 1; }
  virsh -c "$CONN" define "$xml"
}

echo "==> Defining domains on $CONN"
rc=0
define_domain "$REPO/macos-sonoma/macos.xml" || rc=1
define_domain "$REPO/win11/win11.xml"        || rc=1
[ "$rc" -eq 0 ] || echo "   (one or more domains failed to define - see above)"

echo "==> Pointing virt-manager at $CONN"
gsettings set org.virt-manager.virt-manager.connections uris        "['$CONN']" 2>/dev/null || true
gsettings set org.virt-manager.virt-manager.connections autoconnect "['$CONN']" 2>/dev/null || true

# The autoconnect gsetting alone is unreliable - virt-manager can open showing
# "QEMU/KVM User session - Not Connected". Force it on the launcher too.
if [ -f /usr/share/applications/virt-manager.desktop ]; then
  mkdir -p "$HOME/.local/share/applications"
  sed "s|^Exec=virt-manager.*|Exec=virt-manager --connect $CONN|" \
    /usr/share/applications/virt-manager.desktop \
    > "$HOME/.local/share/applications/virt-manager.desktop"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

echo
virsh -c "$CONN" list --all
echo
echo "Done. Launch virt-manager, or: virsh -c $CONN start macos-sonoma"
