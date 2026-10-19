# pf-install-script

A one-step installer for [PokeFields](https://pokefields.com) on Linux. It downloads the latest
release, puts it in a folder in your home directory, and adds PokeFields to your application menu
and desktop. It works on any distro and desktop environment.

** THIS PROJECT IS NOT AFFILIATED WITH THE POKEFIELDS PROJECT IN ANY WAY, DO NOT GO ASKING THEM FOR SUPPORT WITH THIS SCRIPT **

## Quick install

Copy and paste this into a terminal. You don't need to clone anything:

```sh
curl -fsSL https://raw.githubusercontent.com/matthewstocker/pf-install-script/main/install.sh | sh
```

No `curl`? Use `wget` instead:

```sh
wget -qO- https://raw.githubusercontent.com/matthewstocker/pf-install-script/main/install.sh | sh
```

To pass [options](#options) this way, add `-s --` after `sh`. For example, to uninstall:

```sh
curl -fsSL https://raw.githubusercontent.com/matthewstocker/pf-install-script/main/install.sh | sh -s -- --uninstall
```

> These commands work in any shell, including fish and zsh. Don't run them with `sudo`: the game
> installs for your user only, and the script refuses to run as root.

### From a clone

```sh
git clone https://github.com/matthewstocker/pf-install-script.git
cd pf-install-script
sh install.sh
```

## What the script does

1. **Finds the latest release.** It follows `https://update.pokefields.com/download?platform=linux`
   to the current download, which also gives the version number (e.g. `v45`) and the file's
   SHA-256 checksum.
2. **Downloads and verifies it.** The zip is downloaded to a temporary folder and checked against
   that checksum, so a broken or tampered download is rejected before anything is installed.
3. **Installs the game** to `~/Games/PokeFields`. Files are replaced one at a time instead of wiping the
   folder, so anything the game keeps next to itself is kept.
4. **Downloads the game icon** from pokefields.com, since the release zip doesn't include one.
5. **Adds a menu entry** at `~/.local/share/applications/pokefields.desktop`. This is the
   freedesktop.org standard location, read by GNOME, KDE Plasma, XFCE, Cinnamon, MATE, LXQt,
   Budgie and others. PokeFields appears under **Games**.
6. **Adds a desktop shortcut** to your desktop folder, including translated ones like
   `~/Schreibtisch`. It is marked as trusted so GNOME, KDE and XFCE launch it without a
   warning.
7. **Refreshes the menu caches**, so the entry shows up straight away on most desktops.

The installed folder contains:

| File | Purpose |
| --- | --- |
| `pokefields_linux` | The game (the shortcuts launch this) |
| `libpkmn_client.so` | Library the game needs |
| `pokefields-updater` | The game's own updater, which the game runs when a new version is out |
| `icon.png` | Icon used by the shortcuts |
| `.installed-version` | Version this script installed, used to skip repeat downloads |

### Updating

The game updates itself, so you normally only run the script once. Running it again checks for a
new version: if you're already on the latest one it only refreshes the shortcuts, and otherwise it
downloads and installs the update. Use `--force` to re-download anyway, for example to repair a
broken install.

## Options

| Option | Effect |
| --- | --- |
| `-f`, `--force` | Re-download even if the latest version is already installed |
| `--no-desktop-shortcut` | Only create the application-menu entry |
| `--uninstall` | Remove the game and its shortcuts (save data is kept) |
| `-h`, `--help` | Show help |

To install somewhere other than `~/Games/PokeFields`, set `POKEFIELDS_DIR`:

```sh
curl -fsSL https://raw.githubusercontent.com/matthewstocker/pf-install-script/main/install.sh | POKEFIELDS_DIR="$HOME/PokeFields" sh
```

If you install to a custom folder, use the same `POKEFIELDS_DIR` when uninstalling.

## Requirements

- An x86_64 (64-bit Intel/AMD) PC
- `curl` or `wget`
- `unzip`, `bsdtar` or `python3` to extract the download

Almost every desktop distro ships with these already. No root access is needed.

## AI Disclosure

Claude Code was used to assist in writing this script.
