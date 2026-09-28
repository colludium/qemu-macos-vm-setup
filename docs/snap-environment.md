# QEMU dies when launched from a terminal inside a snap

## Symptom

Launching QEMU from an integrated terminal inside snap-packaged VS Code (or any
snap app) fails immediately with:

    qemu-system-x86_64: symbol lookup error:
      /snap/core20/current/lib/x86_64-linux-gnu/libpthread.so.0:
      undefined symbol: __libc_pthread_init, version GLIBC_PRIVATE

The same command works from an ordinary terminal.

## Cause

The snap exports environment variables pointing into its own runtime, and child
processes inherit them. QEMU's GTK display backend then loads the snap's GTK
modules, which pull in the snap's glibc alongside the system one.

`LD_LIBRARY_PATH` is *not* the culprit and is usually empty. The variables that
matter are:

    LOCPATH  PATH  XDG_DATA_DIRS  XDG_DATA_HOME
    GTK_PATH  GTK_EXE_PREFIX  GTK_IM_MODULE_FILE
    GDK_PIXBUF_MODULEDIR  GDK_PIXBUF_MODULE_FILE
    GSETTINGS_SCHEMA_DIR  GIO_MODULE_DIR
    SNAP  SNAP_*

Check yours with:

    env | grep -E "=/snap|/snap/" | cut -d= -f1

## Fix

Scrub them and set a clean `PATH`, `DISPLAY` and `XAUTHORITY`. `macos-sonoma/run.sh`
does this; the essential part is:

    env -u LOCPATH -u GTK_PATH -u GTK_EXE_PREFIX -u GTK_IM_MODULE_FILE \
        -u GDK_PIXBUF_MODULEDIR -u GDK_PIXBUF_MODULE_FILE \
        -u GSETTINGS_SCHEMA_DIR -u GIO_MODULE_DIR -u XDG_DATA_HOME \
        -u SNAP -u SNAP_NAME -u SNAP_REVISION \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$HOME/.Xauthority" \
        qemu-system-x86_64 ...

This affects **any** GUI application launched from a snap terminal, not just
QEMU. It does not affect apps launched from the desktop menu, which get a clean
session environment. Using libvirt/virt-manager avoids it entirely, because
libvirtd spawns QEMU itself.
