#!/usr/bin/env bash
#  /\_/\    SondeR cat installer (Linux — all major distros — and macOS)
# ( o.o )   venv + deps + system-library check + menu entry + launch
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo
echo "   /\\_/\\     SondeR cat installer"
echo "  ( o.o )    ====================="
echo

if [ ! -f "$DIR/sondercat.py" ]; then
    echo "[!] Can't find sondercat.py next to this installer."
    echo "    Extract the whole download, then run ./install.sh from inside it."
    exit 1
fi


# Builds "SondeR cat.app" around the venv. The executable is a small native
# launcher (mac_launcher.c) that embeds the interpreter, so the process is
# called "SondeR cat" everywhere — top, Activity Monitor, crash reports and,
# most usefully, the Privacy & Security lists in System Settings — instead
# of "Python". Needs clang (Command Line Tools); without it we fall back to
# a shell wrapper, which works but shows up as "Python".
mac_build_app() {
    VPY="$DIR/.venv/bin/python"
    APP="$DIR/SondeR cat.app"
    EXE_PATH="$APP/Contents/MacOS/SondeR cat"
    # The privacy permissions are keyed to the app's code hash, and clang
    # doesn't produce byte-identical binaries, so a fresh launcher = a fresh
    # identity = macOS asks for Accessibility & Input Monitoring all over
    # again. Keep the compiled launcher unless mac_launcher.c has changed.
    KEEP=""
    HAD_EXE=0
    [ -e "$EXE_PATH" ] && HAD_EXE=1
    if [ -x "$EXE_PATH" ] && [ ! "$DIR/mac_launcher.c" -nt "$EXE_PATH" ]; then
        KEEP="$DIR/.venv/sondercat-launcher.keep"
        cp "$EXE_PATH" "$KEEP"
    fi
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    BUILT=0
    if [ -n "$KEEP" ]; then
        mv "$KEEP" "$EXE_PATH"
        BUILT=2
    elif command -v clang >/dev/null 2>&1 && [ -f "$DIR/mac_launcher.c" ]; then
        eval "$("$VPY" - << 'PYEOF'
import os, sys, sysconfig, shlex
cv = sysconfig.get_config_var
inc = sysconfig.get_paths()["include"]
libdir = cv("LIBDIR") or os.path.join(sys.base_prefix, "lib")
# python.org / Xcode: a framework binary; Homebrew / conda: a dylib in lib/
# (LDLIBRARY may name a static .a that was never installed, so try several)
cands = [os.path.join(sys.base_prefix, "Python")]
cands += [os.path.join(libdir, n) for n in
          (cv("INSTSONAME"), cv("LDLIBRARY"),
           "libpython%s.dylib" % cv("VERSION")) if n]
lib = next((c for c in cands if os.path.exists(c)), cands[-1])
print("PY_INC=%s" % shlex.quote(inc))
print("PY_LIB=%s" % shlex.quote(lib))
print("PY_LIBDIR=%s" % shlex.quote(libdir))
PYEOF
)"
        if [ -f "$PY_INC/Python.h" ] && [ -f "$PY_LIB" ] && \
           clang -O2 -I"$PY_INC" "$DIR/mac_launcher.c" "$PY_LIB" \
                 -Wl,-rpath,"$PY_LIBDIR" -o "$EXE_PATH" 2>/dev/null; then
            BUILT=1
            if [ "$HAD_EXE" = "1" ]; then
                # new binary = new identity: the old Accessibility / Input
                # Monitoring rows would still show "on" in System Settings
                # while no longer matching the app, so nothing would react.
                # Clear them so macOS asks again with a row that works.
                for svc in Accessibility ListenEvent ScreenCapture; do
                    tccutil reset "$svc" com.verisonder.sondercat >/dev/null 2>&1 || true
                done
                echo "    (launcher rebuilt: macOS will ask for its permissions again)"
            fi
        fi
    fi
    if [ "$BUILT" != "0" ]; then
        # the .app doubles as a venv: same site-packages, own name
        "$VPY" - "$APP/Contents/pyvenv.cfg" << 'PYEOF'
import os, sys
open(sys.argv[1], "w").write("home = %s\ninclude-system-site-packages = false\nversion = %s\n"
                             % (os.path.join(sys.base_prefix, "bin"), sys.version.split()[0]))
PYEOF
        ln -s "../../.venv/lib" "$APP/Contents/lib"
        EXE="SondeR cat"
    else
        echo "    (no clang / Python headers — using a shell launcher; the"
        echo "     process will show up as 'Python'. Install Xcode Command"
        echo "     Line Tools and rerun me for a proper 'SondeR cat' process.)"
        cat > "$APP/Contents/MacOS/sondercat" << EOS
#!/bin/bash
cd "$DIR"
exec "$VPY" "$DIR/sondercat.py"
EOS
        chmod +x "$APP/Contents/MacOS/sondercat"
        EXE="sondercat"
    fi
    # icon: the official cat PNG → .icns (both tools ship with macOS)
    ICON_KEY=""
    if [ -f "$DIR/assets/cat_official.png" ] && command -v iconutil >/dev/null 2>&1 \
        && command -v sips >/dev/null 2>&1; then
        SET="$DIR/.venv/sondercat.iconset"
        rm -rf "$SET"; mkdir -p "$SET"
        for sz in 16 32 128 256 512; do
            sips -z $sz $sz "$DIR/assets/cat_official.png" --out "$SET/icon_${sz}x${sz}.png" >/dev/null 2>&1
            sips -z $((sz*2)) $((sz*2)) "$DIR/assets/cat_official.png" --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1
        done
        if iconutil -c icns "$SET" -o "$APP/Contents/Resources/sondercat.icns" 2>/dev/null; then
            ICON_KEY="    <key>CFBundleIconFile</key><string>sondercat</string>"
        fi
        rm -rf "$SET"
    fi
    cat > "$APP/Contents/Info.plist" << EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SondeR cat</string>
    <key>CFBundleDisplayName</key><string>SondeR cat</string>
    <key>CFBundleIdentifier</key><string>com.verisonder.sondercat</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$EXE</string>
$ICON_KEY
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>SondeR cat reacts to what you do on screen.</string>
</dict>
</plist>
EOS
    # ad-hoc signature: gives the privacy permissions a stable identity to
    # stick to (unsigned apps get re-asked after every rebuild)
    codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
}

# ================================================================= macOS ===
# venv + deps + the .app above + optional login item, then launch. Always
# launch through the .app: macOS attaches the privacy permissions
# (Accessibility, Input Monitoring, Screen Recording) to the app you
# launched, so they stick to the cat instead of to your terminal.
mac_install() {
    if [ "${SONDER_APP_ONLY:-0}" = "1" ] && [ -x "$DIR/.venv/bin/python" ]; then
        echo "Rebuilding 'SondeR cat.app' only..."
        mac_build_app
        exit 0
    fi
    PY=""
    for cand in python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
        if command -v "$cand" >/dev/null 2>&1 && \
           "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
            PY="$(command -v "$cand")"; break
        fi
    done
    if [ -z "$PY" ]; then
        echo "[!] Python 3.9+ not found. Install it with:  brew install python"
        echo "    (or from https://www.python.org/downloads/macos/), then run me again."
        exit 1
    fi
    echo "[1/4] Found $("$PY" --version)  ($PY)"

    echo "[2/4] Creating a private environment (.venv)..."
    "$PY" -m venv "$DIR/.venv"
    echo "[3/4] Installing dependencies (this can take a minute)..."
    "$DIR/.venv/bin/pip" install --upgrade pip --quiet
    "$DIR/.venv/bin/pip" install -r "$DIR/requirements.txt" --quiet

    if [ "${SONDER_CHECK_ONLY:-0}" = "1" ]; then
        echo "(check-only mode: stopping before the .app + launch)"
        exit 0
    fi

    echo "[4/4] Building 'SondeR cat.app'..."
    mac_build_app
    if [ -t 0 ]; then
        printf "Start SondeR cat automatically at login? [y/N] "
        read -r yn
        case "$yn" in
            [Yy]*)
                mkdir -p ~/Library/LaunchAgents
                PL=~/Library/LaunchAgents/com.verisonder.sondercat.plist
                cat > "$PL" << EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.verisonder.sondercat</string>
    <key>ProgramArguments</key>
    <array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOS
                launchctl unload "$PL" >/dev/null 2>&1 || true
                launchctl load "$PL" >/dev/null 2>&1 || true
                echo "Autostart enabled (remove: launchctl unload $PL && rm $PL)." ;;
        esac
    fi

    echo
    echo "All done! Launching your cat..."
    echo
    echo "macOS will ask for two permissions — please allow both, then restart the cat:"
    echo "  • Accessibility     → scroll-paper play and petting/laser hooks"
    echo "  • Input Monitoring  → typing reactions (kneading, overheat)"
    echo "(Screen Recording is asked for only if you turn on the Gemini screen features.)"
    echo "Relaunch any time by double-clicking 'SondeR cat.app' in this folder."
    open "$APP"
    exit 0
}

if [ "$(uname -s)" = "Darwin" ]; then
    mac_install
fi

# ---------------------------------------------------------- detect distro ---
PKG=""
command -v apt-get >/dev/null 2>&1 && PKG="apt"
[ -z "$PKG" ] && command -v dnf     >/dev/null 2>&1 && PKG="dnf"
[ -z "$PKG" ] && command -v pacman  >/dev/null 2>&1 && PKG="pacman"
[ -z "$PKG" ] && command -v zypper  >/dev/null 2>&1 && PKG="zypper"
[ -z "$PKG" ] && command -v apk     >/dev/null 2>&1 && PKG="apk"

venv_hint() {
    case "$PKG" in
        apt)    echo "sudo apt install python3 python3-venv python3-pip" ;;
        dnf)    echo "sudo dnf install python3" ;;
        pacman) echo "sudo pacman -S python" ;;
        zypper) echo "sudo zypper install python3 python3-pip" ;;
        apk)    echo "sudo apk add python3 py3-pip" ;;
        *)      echo "install python3 + venv with your package manager" ;;
    esac
}

syslibs_cmd() {
    case "$PKG" in
        apt)    echo "sudo apt install -y libxcb-cursor0 libgl1 libxkbcommon-x11-0 libegl1" ;;
        dnf)    echo "sudo dnf install -y xcb-util-cursor libxkbcommon-x11 libglvnd-egl" ;;
        pacman) echo "sudo pacman -S --noconfirm xcb-util-cursor libxkbcommon-x11" ;;
        zypper) echo "sudo zypper install -y libxcb-cursor0 libxkbcommon-x11-0" ;;
        apk)    echo "sudo apk add xcb-util-cursor mesa-gl libxkbcommon" ;;
        *)      echo "" ;;
    esac
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "[!] python3 not found. Install it first:"
    echo "      $(venv_hint)"
    exit 1
fi
echo "[1/5] Found $(python3 --version)  (package manager: ${PKG:-unknown})"

echo "[2/5] Creating a private environment (.venv)..."
if ! python3 -m venv "$DIR/.venv" 2>/dev/null; then
    echo "[!] The venv module is missing. Fix with:"
    echo "      $(venv_hint)"
    exit 1
fi

echo "[3/5] Installing dependencies (this can take a minute)..."
"$DIR/.venv/bin/pip" install --upgrade pip --quiet
if [ -f "$DIR/requirements.txt" ]; then
    "$DIR/.venv/bin/pip" install -r "$DIR/requirements.txt" --quiet
else
    "$DIR/.venv/bin/pip" install "PySide6>=6.5" "pynput>=1.7" --quiet
fi

echo "[4/5] Checking system display libraries..."
MISSING=""
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig -p 2>/dev/null | grep -q libxcb-cursor      || MISSING="$MISSING libxcb-cursor"
    ldconfig -p 2>/dev/null | grep -q libxkbcommon-x11   || MISSING="$MISSING libxkbcommon-x11"
    ldconfig -p 2>/dev/null | grep -q 'libGL\.so'        || MISSING="$MISSING libGL"
fi
if [ -n "$MISSING" ]; then
    echo "    Missing:$MISSING"
    CMD="$(syslibs_cmd)"
    if [ -n "$CMD" ] && [ -t 0 ] && [ "${SONDER_CHECK_ONLY:-0}" != "1" ]; then
        printf "    Install them now? [Y/n] "
        read -r yn
        case "$yn" in
            [Nn]*) echo "    Skipped — the cat may not start until you run:"; echo "      $CMD" ;;
            *)     $CMD || { echo "    Couldn't install automatically. Run manually:"; echo "      $CMD"; } ;;
        esac
    else
        echo "    Install them with:"
        echo "      ${CMD:-xcb-cursor + xkbcommon-x11 + GL packages for your distro}"
    fi
else
    echo "    All good."
fi

# session type info
SESSION="${XDG_SESSION_TYPE:-unknown}"
case "$SESSION" in
    wayland)
        if [ -n "${DISPLAY:-}" ]; then
            echo "    Wayland + XWayland detected — the cat will use XWayland (full features)."
        else
            echo "    Pure Wayland (no XWayland) — the cat runs with limited tricks."
            echo "    For everything to work, log into an 'Xorg / X11' session."
        fi ;;
    x11) echo "    X11 session — full features." ;;
esac
command -v gnome-shell >/dev/null 2>&1 && \
    echo "    GNOME note: no system tray by default — right-click the CAT for the menu."

if [ "${SONDER_CHECK_ONLY:-0}" = "1" ]; then
    echo "(check-only mode: stopping before launch)"
    exit 0
fi

echo "[5/5] Creating launcher + app-menu entry..."
cat > "$DIR/start_sondercat.sh" << EOS
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
exec "$DIR/.venv/bin/python" "$DIR/sondercat.py"
EOS
chmod +x "$DIR/start_sondercat.sh"

mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/sondercat.desktop << EOS
[Desktop Entry]
Type=Application
Name=SondeR cat
Comment=A pixel cat for your desktop
Exec=$DIR/start_sondercat.sh
Path=$DIR
Terminal=false
Categories=Utility;
EOS

if [ -t 0 ]; then
    printf "Start SondeR cat automatically at login? [y/N] "
    read -r yn
    case "$yn" in
        [Yy]*) mkdir -p ~/.config/autostart
               cp ~/.local/share/applications/sondercat.desktop ~/.config/autostart/
               echo "Autostart enabled." ;;
    esac
fi

echo
echo "All done! Launching your cat..."
nohup "$DIR/.venv/bin/python" "$DIR/sondercat.py" >/dev/null 2>&1 &
echo "Quit any time: right-click the cat. Relaunch from your app menu."
