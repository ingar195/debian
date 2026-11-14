#!/usr/bin/env bash
# This script uses bash arrays and [[ ]] tests, so it needs bash, not
# POSIX sh/dash. If it's invoked as `sh install.sh` (dash on Debian), the
# shebang above is ignored -- so re-exec ourselves under bash instead of
# failing partway through. This line has to be plain POSIX syntax since
# dash is what parses it the first time round.
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

cd "$(dirname "$0")" || exit 1   # lists and helper files are read from this folder
source functions.sh

set -uo pipefail

# The base install this script targets is "standard system utilities" only.
# git, curl and wget are all used below (check_git_status, the git config
# prompts, and the Docker/VirtualBox gpg key fetches) before install_packages
# "packages" would otherwise install them -- bootstrap the ones that are
# missing up front so those early steps don't fail on a minimal install.
missing_bootstrap_tools=()
for tool in git curl wget; do
    command -v "$tool" &> /dev/null || missing_bootstrap_tools+=("$tool")
done
if [ "${#missing_bootstrap_tools[@]}" -gt 0 ]; then
    logging INFO "Bootstrapping missing tools before anything else: ${missing_bootstrap_tools[*]}"
    sudo apt-get update -qq
    if ! sudo apt-get install -y "${missing_bootstrap_tools[@]}"; then
        logging ERROR "Failed to install ${missing_bootstrap_tools[*]}, cannot continue."
        exit 1
    fi
fi

check_git_status

if [[ -n "${SUDO_USER:-}" || -n "${SUDO_UID:-}" ]]; then
    logging ERROR "You are not allowed to run this script as sudo, exiting in 5 sec"
    sleep 5
    exit 1
fi

if [ -z "$(git config user.email)" ]; then
    read -r -p "Type your git email:  " git_email
    git config --global user.email "$git_email"
fi
if [ -z "$(git config user.name)" ]; then
    read -r -p "Type your git Full name:  " git_name
    git config --global user.name "$git_name"
fi
git config --global init.defaultBranch main
# the keyboard-layout icon ibus puts in the polybar tray
gsettings set org.freedesktop.ibus.panel show-icon-on-systray false 2>/dev/null

sudo install -m 0755 -d /etc/apt/keyrings

if ! sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; then
    logging ERROR "Failed to download Docker gpg key, Docker repo will not be configured"
else
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
fi

# /usr/share/keyrings doesn't exist on a fully minimal install (nothing else
# has created it yet), and gpg won't create missing parent directories for
# --output -- without this, the key write below fails silently and apt
# later can't find the keyring file at all.
sudo install -m 0755 -d /usr/share/keyrings

if ! command -v gpg &> /dev/null; then
    logging INFO "gpg not found, installing gnupg"
    sudo apt-get install -y gnupg || logging ERROR "Failed to install gnupg, VirtualBox key import will fail"
fi
vbox_key_err=$( { wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor; } 2>&1 )
if [ ! -s /usr/share/keyrings/oracle-virtualbox-2016.gpg ]; then
    logging ERROR "Failed to fetch/import VirtualBox gpg key, VirtualBox repo will not be configured: $vbox_key_err"
else
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(. /etc/os-release && echo "$VERSION_CODENAME") contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null
fi

# Tailscale and Claude Desktop are in `packages`, so their apt repos must exist on a fresh PC too.
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
if sudo curl -fsSL "https://pkgs.tailscale.com/stable/debian/$codename.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg; then
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian $codename main" | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null
else
    logging ERROR "Failed to download Tailscale gpg key, Tailscale repo will not be configured"
fi
if sudo curl -fsSL https://downloads.claude.ai/claude-desktop/key.asc -o /usr/share/keyrings/claude-desktop-archive-keyring.asc; then
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop.list > /dev/null
else
    logging ERROR "Failed to download Claude Desktop gpg key, Claude Desktop repo will not be configured"
fi

sudo dpkg --configure -a
if ! sudo apt update 2>/dev/null; then
    logging ERROR "apt update failed, package installs below may fail or be stale"
fi
sudo apt upgrade -y || logging ERROR "apt upgrade failed"

install_packages "packages"
install_code_packages "code_packages"

# Install security tools if -c flag is set
if [ "$sectools" = true ]; then
    install_packages "sec_packages"
fi

# Generate ssh key
if ! ls "$HOME"/.ssh/id_*.pub &> /dev/null; then
    ssh-keygen -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
    logging WARNING "Did not find any SSH key, created a new one. Add this public key to GitHub: $(cat "$HOME/.ssh/id_ed25519.pub")"
fi

# Setting TERM to xterm
# replace_or_append $HOME/.zshrc "export TERM=xterm" "export TERM=xterm"

# user defaults
known_user=false
if [ "$USER" = "user" ] || [ "$USER" = "ingar" ]; then
    known_user=true
    git_url="https://github.com/ingar195/.dotfiles.git"
else
    read -r -p "enter the https URL for your git bare repo: " git_url
fi

# Create directory's
mkdir -p "$HOME/workspace/work" &> /dev/null

# Tmp alias for installation only
# a function, not an alias: aliases are not expanded inside scripts
dotfiles() { /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" "$@"; }

if [[ ! -d "$HOME/.dotfiles/" ]]; then
    logging INFO "Did not find .dotfiles, cloning from $git_url"
    if git clone --bare "$git_url" "$HOME/.dotfiles"; then
        backup_dotfile_conflicts
        if dotfiles checkout -f; then
            logging INFO "Dotfiles successfully checked out."
        else
            logging WARNING "Dotfiles checkout failed. retrying with a clean clone..."
            rm -rf "$HOME/.dotfiles"
            git clone --bare "$git_url" "$HOME/.dotfiles" || logging ERROR "Dotfiles clone failed."
            dotfiles checkout -f || logging ERROR "Dotfiles checkout failed on retry."
        fi
        dotfiles config status.showUntrackedFiles no
    else
        logging ERROR "Dotfiles clone failed, skipping dotfiles setup."
    fi
else
    logging INFO "Updating dotfiles"
    dotfiles pull &> /dev/null || logging ERROR "Dotfiles pull failed."
fi

# A bare clone has no upstream branch, so plain `git push`/`git pull` (the dotp alias) fail without this
if [[ -d "$HOME/.dotfiles/" ]]; then
    dotfiles_branch=$(dotfiles symbolic-ref --short HEAD)
    dotfiles config "branch.$dotfiles_branch.remote" origin
    dotfiles config "branch.$dotfiles_branch.merge" "refs/heads/$dotfiles_branch"
    dotfiles config pull.rebase true
    dotfiles config rebase.autoStash true   # apps (e.g. Variety) rewrite tracked files; a rebase refuses to start with local changes
fi

# The ingar195/.dotfiles repo ships an i3/polybar/variety desktop setup.
# Install the packages it needs (see i3_packages) for the known-user case.
if [ "$known_user" = true ]; then
    install_i3
fi

# System configuration (ported from the Arch installer). Known accounts only,
# and written once, so later hand-edits are not overwritten on re-runs.
if [ "$known_user" = true ]; then
    [ "$(timedatectl show -p Timezone --value)" = Europe/Oslo ] || sudo timedatectl set-timezone Europe/Oslo
    add_to_group video     # brightnessctl without root
    add_to_group dialout   # serial ports (was uucp on Arch)

    # Power saving. Drop-in files, so no sed on the main config files.
    # Locking on suspend is handled by xss-lock in the i3 config.
    write_once /etc/systemd/logind.conf.d/50-installer.conf '[Login]\nHandleLidSwitch=suspend\nIdleAction=suspend\nIdleActionSec=10min\nHoldoffTimeoutSec=5s\n'
    write_once /etc/systemd/system.conf.d/50-installer.conf '[Manager]\nDefaultTimeoutStopSec=10s\n'
    write_once /etc/tlp.d/50-installer.conf 'TLP_ENABLE=1\nCPU_SCALING_GOVERNOR_ON_BAT=powersave\nCPU_SCALING_GOVERNOR_ON_AC=performance\n'

    for svc in NetworkManager bluetooth tlp acpid cups docker; do
        if systemctl cat "$svc.service" &> /dev/null; then
            sudo systemctl enable --now "$svc.service" &> /dev/null || logging ERROR "Failed to enable $svc"
        fi
    done

    # Dark theme and scroll direction: first run only, so a later change in GNOME sticks
    desktop_marker="$HOME/.config/.installer-desktop-defaults"
    if command -v gsettings &> /dev/null && [ ! -f "$desktop_marker" ]; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark &> /dev/null
        gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark &> /dev/null
        gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false &> /dev/null \
            && touch "$desktop_marker"   # no desktop session (ssh/tty): gsettings fails, so retry next run
    fi
fi

# Symbols Nerd Font (polybar icons) -- not packaged in Debian
nerd_dir="$HOME/.local/share/fonts/SymbolsNerdFont"
if [ ! -d "$nerd_dir" ]; then
    logging INFO "Installing Symbols Nerd Font"
    nerd_tmp=$(mktemp -d)
    if curl -fsSL -o "$nerd_tmp/font.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip \
        && mkdir -p "$nerd_dir" && unzip -oq "$nerd_tmp/font.zip" -d "$nerd_dir"; then
        fc-cache -f
    else
        logging ERROR "Failed to install Symbols Nerd Font"
        rm -rf "$nerd_dir"
    fi
    rm -rf "$nerd_tmp"
fi

mkdir -p "$HOME/Pictures/Screenshot"   # Print-screen binding in i3

# Create folders for filemanager
mkdir -p "$HOME/Downloads" &> /dev/null
mkdir -p "$HOME/Desktop" &> /dev/null
mkdir -p "$HOME/Pictures" &> /dev/null
mkdir -p "$HOME/.config/wireguard" &> /dev/null

if [ "$SHELL" != "/usr/bin/zsh" ]; then
    logging INFO "Setting shell"
    sudo chsh -s /usr/bin/zsh "$USER"
    reboot=true
fi

if [ ! -f "$HOME/.oh-my-zsh/README.md" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$HOME/.zshrc"

# Aliases and functions
# Copy .aliases and .functions files to .config
zsh_config_path="$HOME/.config/zsh"
mkdir -p "$zsh_config_path"

cp .aliases "$zsh_config_path/"
cp .functions "$zsh_config_path/"

# Add sources to .zshrc if not already there
add_source_to_zshrc "$zsh_config_path/.aliases"
add_source_to_zshrc "$zsh_config_path/.functions"

# Converts https to ssh
if [ "$skip_convert" = false ]; then
    if [ -f "$HOME/.dotfiles/config" ]; then
        sed -i 's#https://github.com/#git@github.com:#g' "$HOME/.dotfiles/config"
        logging INFO "Converted from https to ssh"
    fi
else
    logging DEBUG "Skipping conversion from https to ssh"
fi

# Diff installed packages against our manifest
unlisted_packages=$(compute_unlisted_packages packages i3_packages sec_packages)
if [ -n "$unlisted_packages" ]; then
    logging WARNING "The following manually-installed packages are not tracked in the installer: $(echo "$unlisted_packages" | tr '\n' ' ')"
fi

if [ "${#newly_installed[@]}" -gt 0 ]; then
    logging INFO "Installed/upgraded this run: $(IFS=,; echo "${newly_installed[*]}")"
fi

# Reboot if any changes were made
if [ "$reboot" = true ]; then
    echo ----------------------
    echo "Please reboot your PC"
    echo ----------------------
fi
