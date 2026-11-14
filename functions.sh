# shellcheck shell=bash
# This file is sourced by install.sh, not run standalone.
# Log messages should be in format    logging INFO MESSAGE
logging() {
    local color_error="\e[31m"
    local color_warning="\e[33m"
    local color_reset="\e[0m"
    local color_info="\e[32m"
    local log_file="log.log"
    local date="[$(date '+%Y-%m-%d %H:%M:%S')]"

    if [[ -z "${DEBUG:-}" && "$1" == "DEBUG" ]]; then
        echo "$date $1: $2" | tee -a "$log_file" &> /dev/null
    else

        case "$1" in
            "ERROR")
            echo -e "${color_error}$1:${color_reset} $2" | tee -a "$log_file"
            ;;
            "WARNING")
            echo -e "${color_warning}$1:${color_reset} $2" | tee -a "$log_file"
            ;;
            "INFO")
            echo -e "${color_info}$1:${color_reset} $2" | tee -a "$log_file"
            ;;
            *)
            echo -e "$1: $2" | tee -a "$log_file"

        esac
    fi
}

# Default option values (may be overridden by getopts below)
DEBUG="${DEBUG:-}"
skip_convert=false
sectools=false

# Define commandline options
optstring=":dsc"
while getopts "$optstring" optchar; do
  case $optchar in
    d)
      DEBUG=true
      ;;
    s)
      skip_convert=true
      logging INFO "Skipping conversion from https to ssh"
      ;;
    c)
        sectools=true
        logging INFO "Adding security tools"
      ;;
    ?)
      echo "Invalid option: -$OPTARG, valid ones -s -d -c" >&2
      exit 1
      ;;
  esac
done

# Tracks whether anything actually changed, so we only recommend a reboot
# when it's warranted (rather than unconditionally every run).
reboot=false

# Packages installed/upgraded this run, populated by install_packages().
# Used for the end-of-run summary in install.sh.
newly_installed=()
deb_packages=()

# Function to add source to .zshrc if not already there
add_source_to_zshrc() {
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -Fxq "source $1" "$HOME/.zshrc"; then
            logging INFO "Adding 'source $1' to .zshrc"
            echo "source $1" >> "$HOME/.zshrc"
        fi
    fi
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Install programs from the input file.
# A line is an apt package name, a direct https URL to a .deb file, or
# "name https://...deb" (when the vendor adds its own apt repo, the name lets us
# skip the big download once it is installed). Blank lines and # comments are ignored.
install_packages() {
    local filename=$1

    if [[ ! -f "$filename" ]]; then
        logging DEBUG "$filename does not exist, skipping (nothing to install)"
        return
    fi

    logging INFO "Installing/checking for new packages from $filename"

    while IFS= read -r package || [[ -n "$package" ]]; do
        # Skip blank lines and comments
        [[ -z "$package" || "$package" == \#* ]] && continue

        local url="" hint="" pkg_name="" pkg_ver inst_ver err_output
        if [[ $package == http://* || $package == https://* ]]; then
            url=$package
        elif [[ $package == *" http://"* || $package == *" https://"* ]]; then
            hint=${package%% *}
            url=${package#* }
        fi

        if [[ -n $url ]]; then
            if [[ -n $hint ]] && is_installed "$hint"; then
                deb_packages+=("$hint")
                logging DEBUG "$hint is already installed, apt keeps it updated. Skipping download..."
                continue
            fi

            if ! err_output=$(curl -fL -o install.deb "$url" 2>&1); then
                logging ERROR "Failed to download $url: $err_output"
                continue
            fi

            pkg_name=$(dpkg-deb -f install.deb Package)
            deb_packages+=("$pkg_name")
            pkg_ver=$(dpkg-deb -f install.deb Version)
            inst_ver=$(dpkg-query -W -f='${Version}' "$pkg_name" 2>/dev/null || true)

            if [ -z "$inst_ver" ]; then
                logging INFO "$pkg_name not found. Installing version $pkg_ver..."
                if err_output=$(sudo DEBIAN_FRONTEND=noninteractive dpkg -i install.deb 2>&1); then
                    newly_installed+=("$pkg_name")
                else
                    logging WARNING "dpkg reported issues installing $pkg_name, attempting to fix dependencies: $err_output"
                fi
                if ! err_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y 2>&1); then
                    logging ERROR "Failed to fix dependencies for $pkg_name: $err_output"
                fi
            elif dpkg --compare-versions "$pkg_ver" gt "$inst_ver"; then
                logging INFO "Upgrading $pkg_name from $inst_ver to $pkg_ver..."
                if err_output=$(sudo DEBIAN_FRONTEND=noninteractive dpkg -i install.deb 2>&1); then
                    newly_installed+=("$pkg_name (upgraded)")
                else
                    logging ERROR "Failed to upgrade $pkg_name: $err_output"
                fi
                sudo DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y &>/dev/null
            else
                logging DEBUG "$pkg_name is up to date ($inst_ver). Skipping..."
            fi
            rm -f install.deb
        elif is_installed "$package"; then
            logging DEBUG "$package is already installed"
        else
            logging INFO "$package is not installed, installing now"
            # noninteractive: output is captured, so a debconf question would hang with no visible prompt
            if err_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" 2>&1); then
                newly_installed+=("$package")
            else
                logging ERROR "Failed to install $package: $(echo "$err_output" | tail -n 3)"
            fi
        fi

        local check_name=${pkg_name:-$package}
        if ! dpkg -s "$check_name" &> /dev/null; then
            logging ERROR "Failed to install $package"
        fi
    done < "$filename"

    if [ "${#newly_installed[@]}" -gt 0 ]; then
        reboot=true
    fi
}

install_code_packages() {
    local filename=$1

    if [[ ! -f "$filename" ]]; then
        logging DEBUG "$filename does not exist, skipping (nothing to install)"
        return
    fi

    if ! command -v code &> /dev/null; then
        logging WARNING "VS Code ('code' command) not found on PATH, skipping extension install. Re-run after installing VS Code."
        return
    fi

    logging INFO "Installing/updating code extensions"
    local installed_extensions
    installed_extensions=$(code --list-extensions)

    while IFS= read -r package || [[ -n "$package" ]]; do
        [[ -z "$package" || "$package" == \#* ]] && continue

        if echo "$installed_extensions" | grep -qixF "$package"; then
            logging DEBUG "$package is already installed"
            continue
        fi
        logging DEBUG "Installing $package"
        code --install-extension "$package" &>/dev/null || logging ERROR "failed to install VS Code extension $package"
    done < "$filename"
}

install_i3() {
    install_packages "i3_packages"
}

# checkout -f overwrites, so first copy every existing file the dotfiles repo tracks into a backup folder
backup_dotfile_conflicts() {
    local backup f
    backup="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    while IFS= read -r f; do
        if [[ -e "$HOME/$f" ]]; then
            mkdir -p "$backup/$(dirname "$f")" && cp -a "$HOME/$f" "$backup/$f"
        fi
    done < <(dotfiles ls-tree -r --name-only HEAD)
    if [[ -d $backup ]]; then
        logging WARNING "Existing files backed up to $backup"
    fi
    return 0
}

# write_once FILE TEXT: create FILE as root only if it is missing, so later hand-edits survive re-runs
# shortcut: never rewrites, so changed values in the script do not reach PCs that already have the file; delete the file to re-apply
write_once() {
    [ -f "$1" ] && return
    sudo install -d "$(dirname "$1")"
    printf '%b' "$2" | sudo tee "$1" > /dev/null
    reboot=true
}

check_git_status() {
    if [[ -n $(git status --porcelain) ]]; then
        logging WARNING "You have unstaged changes in your working directory"
    fi

    # Try to fetch, but timeout after 10 seconds if offline
    if ! timeout 10s git fetch &> /dev/null; then
        logging DEBUG "Could not fetch updates (offline or timeout). Skipping version check."
        return
    fi

    local UPSTREAM
    UPSTREAM=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)

    if [ -z "$UPSTREAM" ]; then
        logging ERROR "No upstream branch set"
        return
    fi

    local BEHIND
    local AHEAD

    # Count how many commits we are behind or ahead
    BEHIND=$(git rev-list --count HEAD.."$UPSTREAM" 2>/dev/null)
    AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD 2>/dev/null)

    if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
        logging ERROR "The git repository has diverged (Ahead: $AHEAD, Behind: $BEHIND)"
    elif [ "$BEHIND" -gt 0 ]; then
        logging WARNING "New version available ($BEHIND commits behind). You should pull this repo."
    elif [ "$AHEAD" -gt 0 ]; then
        logging INFO "You have local commits ($AHEAD) that are not pushed."
    else
        logging INFO "Install script is up-to-date"
    fi
}

add_to_group() {
    local group_name=$1
    if ! groups "$USER" | grep -q "$group_name"; then
        sudo gpasswd -a "$USER" "$group_name"
        reboot=true
    fi
}

# Manually installed apt packages that none of the given list files name.
# System packages (libs, firmware, kernel, task-*, anything above "optional" priority) are ignored.
# shortcut: heuristics, not an exact base-system list; tune the filters if it gets noisy.
compute_unlisted_packages() {
    command -v apt-mark &> /dev/null || return

    local listed
    listed=$( { for f in "$@"; do [ -f "$f" ] && grep -v '^\s*#' "$f" | grep -v '://' | grep -v '^\s*$'; done; printf '%s\n' "${deb_packages[@]}"; } | sort -u)

    comm -23 <(apt-mark showmanual | sort -u) <(echo "$listed") \
        | grep -vE '^(lib|firmware-|linux-|task-|grub|gcc-)' \
        | xargs -r dpkg-query -W -f='${Package} ${Priority} ${Section}\n' 2>/dev/null \
        | awk '($2=="optional"||$2=="extra") && $3!~/^(libs|libdevel|kernel|perl)/ {print $1}'
}
