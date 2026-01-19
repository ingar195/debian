# Log messages should be in format    logging INFO MESSAGE
logging() {
    local color_error="\e[31m"
    local color_warning="\e[33m"
    local color_reset="\e[0m"
    local color_info="\e[32m"
    local log_file="log.log"
    local date="[$(date '+%Y-%m-%d %H:%M:%S')]"

    if [[ -z $DEBUG && $1 == "DEBUG" ]]; then
        echo "$1: $2" | tee -a "$log_file" &> /dev/null
    else

        case $1 in
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


# Function to add source to .zshrc if not already there
add_source_to_zshrc() {
    if [[ -f $HOME/.zshrc ]]; then
        if ! grep -Fxq "source $1" $HOME/.zshrc; then
            logging INFO "Adding 'source $1 to .zshrc'"
            echo "source $1" >> $HOME/.zshrc
        fi
    fi
}

# Install programs from the input file
install_packages() {
    logging INFO "Installing/checking for new packages from $1"
    local filename=$1
    while IFS= read -r package || [[ -n "$package" ]]; do
        
        if echo "$package" | grep -q "http"; then
            curl -L -o install.deb "$package" &>/dev/null
            
            local pkg_name
            local pkg_ver
            local inst_ver
            
            pkg_name=$(dpkg-deb -f install.deb Package)
            pkg_ver=$(dpkg-deb -f install.deb Version)
            inst_ver=$(dpkg-query -W -f='${Version}' "$pkg_name" 2>/dev/null)

            if [ -z "$inst_ver" ]; then
                logging INFO "$pkg_name not found. Installing version $pkg_ver..."
                sudo dpkg -i install.deb &>/dev/null
                sudo apt-get --fix-broken install -y &>/dev/null
            elif dpkg --compare-versions "$pkg_ver" gt "$inst_ver"; then
                logging INFO "Upgrading $pkg_name from $inst_ver to $pkg_ver..."
                sudo dpkg -i install.deb &>/dev/null
                sudo apt-get --fix-broken install -y &>/dev/null
            else
                logging DEBUG "$pkg_name is up to date ($inst_ver). Skipping..."
            fi
            rm install.deb
        else
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
                logging DEBUG "$package is already installed"
            else
                logging INFO "$package is not installed, installing now"
                sudo apt-get install -y "$package" &>/dev/null
            fi
        fi

        local check_name
        if echo "$package" | grep -q "http"; then
             check_name="$pkg_name"
        else
             check_name="$package"
        fi
        
        # This check is fine, dpkg -s is stable
        if ! dpkg -s "$check_name" &> /dev/null; then
            logging ERROR "Failed to install $package"
        fi
    done < "$filename"
}

install_code_packages() {
    logging INFO "Installing/updating code extensions"
    local filename=$1
    local installed_extensions=$(code --list-extensions)
    while IFS= read -r package || [[ -n "$package" ]]; do
        logging DEBUG Installing "$package"
        if echo "$installed_extensions" | grep -E "^$package" &> /dev/null; then
            logging DEBUG "$package is already installed"
            continue
        fi
        code --install-extension "$package" &>/dev/null || logging ERROR "failed to install VS Code extensions $package"
    done < "$filename"
}

replace_or_append() {
  local file="$1"  # Target file
  local target="$2" # Line to replace (target string)
  local replacement="$3" # Replacement line
  logging DEBUG "Replacing or appending $target with $replacement in $file"

  if [ -z "$4" ]; then
    local sudo=""
  else
    local sudo="sudo"
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
        $sudo sh -c "$sudo echo $replacement >> $file"
        logging INFO "Added line in file: $file"
    fi
fi
}

install_i3() {
    git_url="https://github.com/ingar195/.dotfiles.git"

    install_packages "i3_packages"


    if [ ! -f "$HOME/.dotfiles/config" ];then
        rm .config/i3/config
        mkdir .config/polybar
    fi
}

check_git_status() {
    if [[ -n $(git status --porcelain) ]]; then
        logging WARNING "You have unstaged changes in your working directory"
    fi

    # Try to fetch, but timeout after 3 seconds if offline
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
        logging INFO "Install script is Up-to-date"
    fi
}

add_to_group (){
    local group_name=$1
    if ! groups $USER | grep -q "$group_name"; then
        sudo gpasswd -a $USER $group_name
        reboot=true
    fi
}