#!/bin/sh
# PokeFields installer for Linux.
#
# Downloads the latest PokeFields release, installs it into a folder in your
# home directory and creates an application-menu entry plus a desktop shortcut
# using the freedesktop.org standards, so it works on any desktop environment
# (GNOME, KDE Plasma, XFCE, Cinnamon, MATE, LXQt, Budgie, ...) and any distro.
#
# Usage: sh install.sh [--force] [--no-desktop-shortcut] [--uninstall]
#
# Re-running the script updates an existing install. The game also updates
# itself, so this is only needed for the first install or to repair one.
#
# Environment overrides:
#   POKEFIELDS_DIR   install location (default: ~/Games/PokeFields)

set -eu

DOWNLOAD_URL="https://update.pokefields.com/download?platform=linux"
ICON_URL="https://pokefields.com/icon.png"
APP_ID="pokefields"
APP_NAME="PokeFields"
GAME_EXE="pokefields_linux"

INSTALL_DIR="${POKEFIELDS_DIR:-$HOME/Games/PokeFields}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/512x512/apps"
MENU_ENTRY="$APPS_DIR/$APP_ID.desktop"

FORCE=0
DESKTOP_SHORTCUT=1
UNINSTALL=0

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    # Kept inline rather than read from "$0", which is just "sh" when piped from curl.
    cat <<EOF
Usage: sh install.sh [--force] [--no-desktop-shortcut] [--uninstall]

  -f, --force             re-download even if the latest version is installed
  --no-desktop-shortcut   only create the application-menu entry
  --uninstall             remove the game and its shortcuts
  -h, --help              show this help

Environment overrides:
  POKEFIELDS_DIR   install location (default: ~/Games/PokeFields)
EOF
    exit "${1:-0}"
}

for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        --no-desktop-shortcut) DESKTOP_SHORTCUT=0 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage 0 ;;
        *) warn "unknown option: $arg"; usage 1 >&2 ;;
    esac
done

# --- helpers ----------------------------------------------------------------

# Print the user's desktop folder (localised, e.g. ~/Schreibtisch), if any.
desktop_dir() {
    dir=""
    if have xdg-user-dir; then
        dir=$(xdg-user-dir DESKTOP 2>/dev/null || true)
    fi
    if [ -z "$dir" ] && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]; then
        dir=$(sed -n 's/^XDG_DESKTOP_DIR="\(.*\)"/\1/p' \
            "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" | sed "s|\$HOME|$HOME|")
    fi
    [ -n "$dir" ] || dir="$HOME/Desktop"
    # xdg-user-dir falls back to $HOME when no desktop folder is configured.
    if [ "$dir" != "$HOME" ] && [ -d "$dir" ]; then
        printf '%s\n' "$dir"
    fi
}

# Quote a path for a .desktop Exec= key (Desktop Entry Spec, "The Exec key").
exec_quote() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\\\\\/g; s/"/\\\\"/g; s/`/\\\\`/g; s/\$/\\\\$/g')"
}

# Escape a plain string value (Path=, Icon=) for a .desktop file.
desktop_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g'
}

refresh_caches() {
    have update-desktop-database && update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
    have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$DATA_HOME/icons/hicolor" 2>/dev/null || true
    have kbuildsycoca6 && kbuildsycoca6 >/dev/null 2>&1 || \
        { have kbuildsycoca5 && kbuildsycoca5 >/dev/null 2>&1; } || true
}

download() { # url dest
    if have curl; then
        curl -fL --retry 3 --progress-bar -o "$2" "$1"
    else
        wget -q --show-progress -O "$2" "$1"
    fi
}

# Follow redirects and print the final URL without downloading the body.
resolve_url() {
    if have curl; then
        curl -fsIL -o /dev/null -w '%{url_effective}' "$1"
    else
        wget --spider -S "$1" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r'
    fi
}

extract_zip() { # zip dest
    if have unzip; then
        unzip -q -o "$1" -d "$2"
    elif have bsdtar; then
        bsdtar -xf "$1" -C "$2"
    elif have python3; then
        python3 -I -m zipfile -e "$1" "$2"
    else
        die "need one of: unzip, bsdtar, python3 to extract the game"
    fi
}

# --- uninstall --------------------------------------------------------------

if [ "$UNINSTALL" -eq 1 ]; then
    info "Removing $APP_NAME"
    rm -f "$MENU_ENTRY" "$ICON_DIR/$APP_ID.png"
    ddir=$(desktop_dir || true)
    [ -n "$ddir" ] && rm -f "$ddir/$APP_ID.desktop"
    if [ -f "$INSTALL_DIR/$GAME_EXE" ] && [ "$INSTALL_DIR" != "$HOME" ]; then
        rm -rf "$INSTALL_DIR"
    elif [ -d "$INSTALL_DIR" ]; then
        warn "$INSTALL_DIR does not look like a PokeFields install; left it alone"
    fi
    refresh_caches
    info "Uninstalled. Save data (if any) under ~/.local/share/godot was kept."
    exit 0
fi

# --- preflight --------------------------------------------------------------

[ "$(id -u)" -ne 0 ] || die "do not run this as root; it installs for your user only"
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "PokeFields for Linux is x86_64 only (this machine is $(uname -m))" ;;
esac
have curl || have wget || die "need curl or wget to download the game"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pokefields-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

# --- download ---------------------------------------------------------------

info "Checking for the latest release"
REAL_URL=$(resolve_url "$DOWNLOAD_URL") || die "could not reach $DOWNLOAD_URL"
# URLs look like https://dl.pokefields.com/linux/v45/<sha256>/pokefields_linux.zip
VERSION=$(printf '%s\n' "$REAL_URL" | sed -n 's|.*/linux/\(v[0-9][^/]*\)/.*|\1|p')
SHA256=$(printf '%s\n' "$REAL_URL" | sed -n 's|.*/\([0-9a-f]\{64\}\)/[^/]*$|\1|p')
[ -n "$VERSION" ] || VERSION="unknown"

if [ "$FORCE" -eq 0 ] && [ "$VERSION" != "unknown" ] && [ -x "$INSTALL_DIR/$GAME_EXE" ] \
    && [ "$(cat "$INSTALL_DIR/.installed-version" 2>/dev/null)" = "$VERSION" ]; then
    info "$APP_NAME $VERSION is already installed; refreshing shortcuts only (use --force to reinstall)"
else
    info "Downloading $APP_NAME $VERSION"
    download "$REAL_URL" "$TMP/pokefields.zip" || die "download failed"

    if [ -n "$SHA256" ] && have sha256sum; then
        info "Verifying checksum"
        printf '%s  %s\n' "$SHA256" "$TMP/pokefields.zip" | sha256sum -c --quiet - \
            || die "checksum mismatch; the download is corrupt, try again"
    fi

    info "Extracting"
    mkdir -p "$TMP/extract"
    extract_zip "$TMP/pokefields.zip" "$TMP/extract"
    [ -f "$TMP/extract/$GAME_EXE" ] || die "unexpected archive layout: $GAME_EXE not found"

    info "Installing to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    # Replace files one by one (rather than wiping the folder) so anything the
    # game keeps next to itself survives an update.
    for f in "$TMP/extract"/* "$TMP/extract"/.[!.]*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        rm -rf "$INSTALL_DIR/$name"
        mv "$f" "$INSTALL_DIR/$name"
    done
    chmod +x "$INSTALL_DIR/$GAME_EXE"
    [ -f "$INSTALL_DIR/pokefields-updater" ] && chmod +x "$INSTALL_DIR/pokefields-updater"
    printf '%s\n' "$VERSION" > "$INSTALL_DIR/.installed-version"
fi

# --- icon -------------------------------------------------------------------

ICON_PATH="$INSTALL_DIR/icon.png"
if [ ! -s "$ICON_PATH" ] || [ "$FORCE" -eq 1 ]; then
    info "Downloading icon"
    if download "$ICON_URL" "$TMP/icon.png" 2>/dev/null && [ -s "$TMP/icon.png" ]; then
        mv "$TMP/icon.png" "$ICON_PATH"
    else
        warn "could not download the icon; shortcuts will use a generic one"
    fi
fi
if [ -s "$ICON_PATH" ]; then
    mkdir -p "$ICON_DIR"
    cp "$ICON_PATH" "$ICON_DIR/$APP_ID.png"
    # An absolute path works in every desktop, even ones that ignore icon themes.
    ICON_VALUE=$(desktop_escape "$ICON_PATH")
else
    ICON_VALUE="applications-games"
fi

# --- shortcuts --------------------------------------------------------------

info "Creating application menu entry"
mkdir -p "$APPS_DIR"
cat > "$MENU_ENTRY" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=$APP_NAME
GenericName=Game
Comment=Play $APP_NAME
Exec=$(exec_quote "$INSTALL_DIR/$GAME_EXE")
Path=$(desktop_escape "$INSTALL_DIR")
Icon=$ICON_VALUE
Terminal=false
Categories=Game;
Keywords=pokefields;pokemon;game;
StartupNotify=true
PrefersNonDefaultGPU=true
EOF
chmod +x "$MENU_ENTRY"

if have desktop-file-validate; then
    desktop-file-validate "$MENU_ENTRY" >&2 || warn "desktop-file-validate reported problems"
fi

if [ "$DESKTOP_SHORTCUT" -eq 1 ]; then
    ddir=$(desktop_dir || true)
    if [ -n "$ddir" ]; then
        info "Creating desktop shortcut in $ddir"
        shortcut="$ddir/$APP_ID.desktop"
        cp "$MENU_ENTRY" "$shortcut"
        # Most file managers (KDE, Cinnamon, MATE, LXQt) only need +x to trust it.
        chmod +x "$shortcut"
        if have gio; then
            # GNOME (Desktop Icons NG) and Nautilus-based desktops.
            gio set "$shortcut" metadata::trusted true 2>/dev/null || true
            # XFCE 4.18+ trusts launchers whose checksum matches this attribute.
            if have sha256sum; then
                gio set -t string "$shortcut" metadata::xfce-exe-checksum \
                    "$(sha256sum "$shortcut" | cut -d' ' -f1)" 2>/dev/null || true
            fi
        fi
    else
        info "No desktop folder found; skipping desktop shortcut"
    fi
fi

refresh_caches

info "$APP_NAME $VERSION installed to $INSTALL_DIR"
info "Launch it from your applications menu, or run: \"$INSTALL_DIR/$GAME_EXE\""
