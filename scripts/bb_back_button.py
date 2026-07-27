#!/usr/bin/env python3
"""Make the mouse's back button act as "go back" inside BlueBubbles only.

How it stays scoped (this is the important part):
  It listens for XInput2 *raw* button events on the root window. Raw events are
  observational -- they do NOT grab the button, so the press still reaches
  whatever window is under the cursor exactly as before. In a browser the back
  button keeps doing browser-back; nothing is intercepted, swallowed or
  replayed. The only thing this adds is: when the focused window is BlueBubbles,
  it also synthesises the key BlueBubbles treats as "back".

Match on the stable WM_CLASS "bluebubbles"/"Bluebubbles". BlueBubbles' Flutter
build also makes helper windows with a random per-launch class (e.g.
"zBGqqegECb"), which must never be matched.

Implementation notes:
  - python-xlib (0.33) does not decode XI2 raw events, so ev.data arrives as
    raw bytes. Layout, verified empirically against known button numbers:
        [0:2] deviceid, [2:6] time, [6:10] detail (button number, LE uint32)
  - Selecting AllDevices delivers the same press twice (once for the physical
    slave device, once for the master pointer), which would send the back key
    twice and pop two screens. AllMasterDevices gives exactly one event.

Config via env:
  BB_BACK_BUTTON  X button number to react to (default 8)
  BB_BACK_KEY     key to send to BlueBubbles  (default Escape)
  BB_BACK_DEBUG   1 = log every press and the focused class

Run with --detect to just print the button number of whatever you press; use it
to confirm which button your mouse's back button actually is.
"""
import fcntl
import os
import subprocess
import sys
import tempfile

try:
    from Xlib import X, display
    from Xlib.ext import xinput
except ImportError:
    # Not installed on every machine. Exit quietly rather than leaving a broken
    # autostart entry: install python-xlib (pacman -S python-xlib) to enable.
    sys.stderr.write("bb_back_button: python-xlib not installed; back button remap disabled\n")
    sys.exit(0)

BUTTON = int(os.environ.get("BB_BACK_BUTTON", "8"))
KEY = os.environ.get("BB_BACK_KEY", "Escape")
DEBUG = os.environ.get("BB_BACK_DEBUG") == "1"
DETECT = "--detect" in sys.argv
TARGET_CLASS = "bluebubbles"


def detail_of(ev):
    """Button number out of an undecoded XI2 raw event."""
    data = getattr(ev, "data", None)
    if not isinstance(data, (bytes, bytearray)) or len(data) < 10:
        return None
    return int.from_bytes(data[6:10], "little")


def focused_class(dpy, root, atom):
    try:
        prop = root.get_full_property(atom, X.AnyPropertyType)
        if not prop or not prop.value:
            return None
        win = dpy.create_resource_object("window", prop.value[0])
        cls = win.get_wm_class()
        if not cls:
            return None
        return cls[1] or cls[0]  # (instance, class)
    except Exception:
        return None


def acquire_single_instance_lock():
    """Exit quietly if a daemon is already running.

    i3 runs this from exec_always, which fires again on every reload/restart.
    A lock is used rather than a pkill guard because a pkill pattern broad
    enough to match the daemon also matches the very command line launching it,
    so the guard kills its own shell before the daemon ever starts.
    """
    path = os.path.join(tempfile.gettempdir(), f"bb_back_button.{os.getuid()}.lock")
    handle = open(path, "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)
    return handle  # keep referenced so the lock is held for process lifetime


def main():
    lock = acquire_single_instance_lock()  # noqa: F841

    dpy = display.Display()
    if not dpy.has_extension("XInputExtension"):
        sys.exit("XInput extension missing")

    root = dpy.screen().root
    atom = dpy.intern_atom("_NET_ACTIVE_WINDOW")

    # Master devices only -> one event per physical press.
    # RawButtonPress only -> no motion traffic, so this stays idle-cheap even
    # with a high-polling-rate gaming mouse.
    xinput.select_events(root, [(xinput.AllMasterDevices, xinput.RawButtonPressMask)])
    dpy.flush()

    if DETECT:
        print("Press mouse buttons to see their X button number. Ctrl-C to stop.", flush=True)
    elif DEBUG:
        print(f"listening: button={BUTTON} key={KEY}", flush=True)

    while True:
        ev = dpy.next_event()
        detail = detail_of(ev)
        if detail is None:
            continue

        if DETECT:
            print(f"button {detail}   (focused: {focused_class(dpy, root, atom)!r})", flush=True)
            continue

        if detail != BUTTON:
            continue

        cls = focused_class(dpy, root, atom)
        if DEBUG:
            print(f"button {BUTTON} pressed; focused class={cls!r}", flush=True)

        if cls and cls.lower() == TARGET_CLASS:
            subprocess.run(
                ["xdotool", "key", "--clearmodifiers", KEY],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if DEBUG:
                print(f"  -> sent {KEY} to BlueBubbles", flush=True)


if __name__ == "__main__":
    main()
