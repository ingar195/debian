# Debian Installer

## Description
Post-install setup script for Debian — the "v2" of [ingar195/Arch](https://github.com/ingar195/Arch), since I've moved to Debian as my primary OS for laptops.

## Installation
1. Install Debian with a desktop environment that brings a display manager (e.g. GNOME with `gdm3`). The script adds X11 and i3 on top, and i3 shows up as a session at the login screen. No display manager is installed.
2. Boot into the fresh install (no chroot needed).
3. Navigate to where you want to store the script.
4. Clone the repository: `git clone https://github.com/ingar195/debian.git`
5. `cd` into the `debian` folder.
6. Run the script: `bash install.sh` (must be run with bash — it uses arrays and `[[ ]]` tests that plain `sh`/`dash` doesn't support).
7. Reboot the PC if prompted.

## Dotfiles
Dotfiles is what we've named the git bare repo used for backing up OS settings and non-sensitive files. For the `ingar`/`user` accounts, `install.sh` clones [ingar195/.dotfiles](https://github.com/ingar195/.dotfiles) (or updates it if already present) and exposes it through the `dotfiles` alias. Any other account is prompted for its own bare-repo URL. That repo currently ships an i3/polybar/variety desktop config, so for the known accounts `install.sh` also installs the packages listed in `i3_packages` (see below) right after the dotfiles checkout.

## Usage
```
bash install.sh [-s -d -c]
```
* `-s` skips converting the dotfiles repo remote from HTTPS to SSH (mostly used for testing)
* `-d` enables debug logging to the console
* `-c` also installs the packages listed in `sec_packages`

## Features
* Updates the PC (`apt update && apt upgrade`)
* Sets up git username and email if not already configured
* Adds the Docker and VirtualBox apt repositories
* Installs all packages from the `packages` file (supports both plain apt package names and direct `.deb` URLs)
* Installs VS Code extensions from `code_packages` (skipped with a warning if `code` isn't installed yet)
* Optionally installs `sec_packages` when `-c` is passed
* Generates an SSH key if one doesn't exist
* Clones/updates the dotfiles bare repo, installs its i3/polybar/variety dependencies from `i3_packages` — including X11 (known accounts only) — and converts the dotfiles remote from HTTPS to SSH (unless `-s` is passed)
* Configures zsh: sets it as the login shell, installs Oh My Zsh, sets the `agnoster` theme, deploys `.aliases`/`.functions` into `~/.config/zsh` and sources them from `.zshrc`
* Creates standard folders (`workspace/work`, `Downloads`, `Desktop`, `Pictures`, `.config/wireguard`)
* Reports any manually-installed apt packages that aren't tracked in `packages`
* Only recommends a reboot when something that actually needs one changed (new packages, shell change, group membership)

## Aliases and functions
- `dotfiles`  — alias for using the dotfiles bare repo (git-dir/work-tree shortcut)
- `dotp`      — quickly commit and push all changes to files already tracked in dotfiles
- `rs`        — `rsync` with our preferred flags
- `cansetup`  — sets up can-bus for use with can-utils
- `wg` / `wgd`   — connect/disconnect WireGuard using `~/.config/wireguard/wg0.conf`
- `wgh` / `wghd` — connect/disconnect WireGuard using `~/.config/wireguard/wg1.conf`
- `lll`       — tree view
- `py` / `python` — run Python 3
- `cpu`       — live per-thread core clock watch
- `ports`     — `ss -tulpn`
- `install` / `uninstall` — thin wrappers around `apt-get install` / `apt-get remove --purge`
- `update`    — pulls the latest version of this repo and re-runs `install.sh`

## Package/extension lists
- `packages` — apt packages and direct `.deb` download URLs installed on every run
- `code_packages` — VS Code extension IDs
- `sec_packages` — extra packages installed only with `-c` (empty by default — add your own)
- `i3_packages` — packages for the i3/polybar/variety desktop setup shipped by the dotfiles repo (`install_i3`, auto-run for the `ingar`/`user` accounts)

Any of these files may contain blank lines or `#` comments — both are ignored.
