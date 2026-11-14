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

# Function to add source to .zshrc if not already there
add_source_to_zshrc() {
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -Fxq "source $1" "$HOME/.zshrc"; then
            logging INFO "Adding 'source $1' to .zshrc"
            echo "source $1" >> "$HOME/.zshrc"
        fi
    fi
}

# Install programs from the input file.
# Lines may be a plain apt package name, a direct https URL to a .deb file,
# blank, or a comment starting with #.
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

        if echo "$package" | grep -q "http"; then
            local pkg_name
            local pkg_ver
            local inst_ver
            local err_output

            if ! err_output=$(curl -fL -o install.deb "$package" 2>&1); then
                logging ERROR "Failed to download $package: $err_output"
                continue
            fi

            pkg_name=$(dpkg-deb -f install.deb Package)
            pkg_ver=$(dpkg-deb -f install.deb Version)
            inst_ver=$(dpkg-query -W -f='${Version}' "$pkg_name" 2>/dev/null || true)

            if [ -z "$inst_ver" ]; then
                logging INFO "$pkg_name not found. Installing version $pkg_ver..."
                if err_output=$(sudo dpkg -i install.deb 2>&1); then
                    newly_installed+=("$pkg_name")
                else
                    logging WARNING "dpkg reported issues installing $pkg_name, attempting to fix dependencies: $err_output"
                fi
                if ! err_output=$(sudo apt-get --fix-broken install -y 2>&1); then
                    logging ERROR "Failed to fix dependencies for $pkg_name: $err_output"
                fi
            elif dpkg --compare-versions "$pkg_ver" gt "$inst_ver"; then
                logging INFO "Upgrading $pkg_name from $inst_ver to $pkg_ver..."
                if err_output=$(sudo dpkg -i install.deb 2>&1); then
                    newly_installed+=("$pkg_name (upgraded)")
                else
                    logging ERROR "Failed to upgrade $pkg_name: $err_output"
                fi
                sudo apt-get --fix-broken install -y &>/dev/null
            else
                logging DEBUG "$pkg_name is up to date ($inst_ver). Skipping..."
            fi
            rm -f install.deb
        else
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
                logging DEBUG "$package is already installed"
            else
                logging INFO "$package is not installed, installing now"
                local err_output
                if err_output=$(sudo apt-get install -y "$package" 2>&1); then
                    newly_installed+=("$package")
                else
                    logging ERROR "Failed to install $package: $(echo "$err_output" | tail -n 3)"
                fi
            fi
        fi

        local check_name
        if echo "$package" | grep -q "http"; then
             check_name="$pkg_name"
        else
             check_name="$package"
        fi

        # This check is fine, dpkg -s is stable
        if [ -n "$check_name" ] && ! dpkg -s "$check_name" &> /dev/null; then
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

        if echo "$installed_extensions" | grep -E "^$package" &> /dev/null; then
            logging DEBUG "$package is already installed"
            continue
        fi
        logging DEBUG "Installing $package"
        code --install-extension "$package" &>/dev/null || logging ERROR "failed to install VS Code extension $package"
    done < "$filename"
}

replace_or_append() {
  local file="$1"  # Target file
  local target="$2" # Line to replace (target string)
  local replacement="$3" # Replacement line
  logging DEBUG "Replacing or appending $target with $replacement in $file"

  local sudo=""
  if [ -n "${4:-}" ]; then
    sudo="sudo"
  fi

  if [ ! -f "$file" ]; then
    $sudo touch "$file"
    logging INFO "Created file: $file"
  fi

  # Use grep to check if target exists (avoids unnecessary sed invocation)
  if $sudo grep -qE "^$replacement$" "$file"; then
    logging DEBUG "Replacement already exists in file: $file"
  else
    if $sudo grep -qE "^$target$" "$file"; then
        $sudo sed -i "/^$target/s//$replacement/" "$file"
        logging INFO "Changed line in file: $file"
    else
        # Append replacement if target not found
        echo "$replacement" | $sudo tee -a "$file" > /dev/null
        logging INFO "Added line in file: $file"
    fi
  fi
}

install_i3() {
    install_packages "i3_packages"

    if [ ! -f "$HOME/.dotfiles/config" ]; then
        rm -f "$HOME/.config/i3/config"
        mkdir -p "$HOME/.config/polybar"
    fi
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

# Compares apt packages installed manually on this system against the ones
# tracked in our "packages" manifest, and prints (one per line) the ones we
# didn't install and don't know about. Used for the end-of-run summary.
compute_unlisted_packages() {
    local packages_file="${1:-packages}"

    if ! command -v apt-mark &> /dev/null; then
        return
    fi

    local listed
    listed=$( { [ -f "$packages_file" ] && grep -v '^#' "$packages_file" | grep -v 'http' | grep -v '^\s*$'; } | sort -u)

    local manual
    manual=$(apt-mark showmanual | sort -u)

    comm -23 <(echo "$manual") <(echo "$listed")
}
