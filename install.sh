# Logg messages should be in format    logging INFO MESSAGE
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

# Install progans from the input file
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
                sudo dpkg -i install.deb
                sudo apt --fix-broken install -y &>/dev/null
            elif dpkg --compare-versions "$pkg_ver" gt "$inst_ver"; then
                logging INFO "Upgrading $pkg_name from $inst_ver to $pkg_ver..."
                sudo dpkg -i install.deb
                sudo apt --fix-broken install -y &>/dev/null
            else
                logging DEBUG "$pkg_name is up to date ($inst_ver). Skipping..."
            fi
            rm install.deb
        else
            if apt list --installed "$package" 2>/dev/null | grep -q "installed"; then
                logging DEBUG "$package is already installed"
            else
                logging INFO "$package is not installed, installing now"
                sudo apt install -y "$package" &>/dev/null
            fi
        fi

        local check_name
        if echo "$package" | grep -q "http"; then
             check_name="$pkg_name"
        else
             check_name="$package"
        fi
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
        # Perform in-place replacement with sed (consider using a temporary file for safety)
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
    if ! timeout 3s git fetch &> /dev/null; then
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

check_git_status

if [[ -n "$SUDO_USER" || -n "$SUDO_UID" ]]; then
    logging ERROR "You are not allowed to run this script as sudo, exiting in 5 sec"
    sleep 5
    exit 1
fi

# Update apt database
sudo apt update
sudo apt upgrade -y


if [ -z "$(git config user.email)" ]; then
    read -p "Type your git email:  " git_email
    git config --global user.email "$git_email"
    
fi
if [ -z "$(git config user.name)" ]; then
    read -p "Type your git Full name:  " git_name
    git config --global user.name "$git_name"
fi


# Add user to uucp group to allow access to serial ports
# TODO: this should be a function now 
if ! groups $USER | grep &>/dev/null '\buucp\b'; then
    sudo gpasswd -a $USER uucp
    reboot=true
fi

# TODO: install docker
# Add Docker's official GPG key:
sudo install -m 0755 -d /etc/apt/keyrings
if [[ -f /etc/apt/keyrings/docker.asc ]]; then
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

fi


wget -O- https://www.virtualbox.org | sudo gpg --dearmor --yes --output /usr/share/keyrings/oracle-vbox.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-vbox.gpg] https://download.virtualbox.org $(lsb_release -cs) contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

sudo usermod -aG vboxusers $USER




sudo apt update
install_packages "packages"
install_code_packages "code_packages"

# Install security tools if -c flag is set
if [ -n "$sectools" ]; then
    install_packages "sec_packages"
fi

# Generate ssh key
if [[ ! -f $HOME/.ssh/id_rsa ]]
then
    ssh-keygen -m PEM -N '' -f ~/.ssh/id_rsa
    logging WARNING "Did not find any SSH key, created a new one"
fi



# Setting TERM to xterm
# replace_or_append $HOME/.zshrc "export TERM=xterm" "export TERM=xterm"

# user defaults

if [ "$USER" = "user" ] || [ "$USER" = "ingar" ]; then

    # Create directory's
    mkdir -p $HOME/workspace/work &> /dev/null
    
    # install_i3
    skip_convert=false
else
    read -p "enter the https URL for you git bare repo: " git_url
fi

# Tmp alias for installation only 
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=/home/$USER'

# if [[ ! -d $HOME/.dotfiles/ ]]
# then
#     logging INFO "Did not find .dotfiles, so will check them out again"
#     git clone --bare $git_url $HOME/.dotfiles 
#     dotfiles checkout -f || logging ERROR "Dotfiles checkout failed."
#     if [ $? -ne 0 ]; then
#         logging WARNING "Dotfiles pull failed. retrying..."
#         sudo rm -rf $HOME/.dotfiles
#         git clone --bare $git_url $HOME/.dotfiles
#     else
#         logging INFO "Dotfiles Successfully checked out."
#     fi
# else
#     logging INFO "Updating dotfiles"
#     dotfiles pull &> /dev/null || logging ERROR "Dotfiles pull failed."    
# fi

# Create folders for filemanager
mkdir -p $HOME/Downloads &> /dev/null
mkdir -p $HOME/Desktop &> /dev/null
mkdir -p $HOME/Pictures &> /dev/null
mkdir -p $HOME/.config/wireguard &> /dev/null


if [ "$(echo $SHELL )" != "/bin/zsh" ]; then
    sudo chsh -s /bin/zsh $USER
fi

if [ ! -f $HOME/.oh-my-zsh/README.md ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    # replace_or_append $HOME/.zshrc "ZSH_THEME=\"robbyrussell\"" "ZSH_THEME=\"agnoster\""
fi
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' $HOME/.zshrc

# Aliases and functions
# Copy .aliases and .functions files to .config
zsh_config_path=$HOME/.config/zsh
mkdir -p $zsh_config_path

cp .aliases $zsh_config_path/
cp .functions $zsh_config_path/

sudo sed -i "s|script_path|$PWD|g" $HOME/.config/zsh/.functions

# Add sources to .zshrc if not already there
# add_source_to_zshrc "$zsh_config_path/.aliases"
add_source_to_zshrc "$zsh_config_path/.functions"

file_to_source="$zsh_config_path/.work"

if [[ $zsh_work == "y" ]] && ! grep -q "$file_to_source" ~/.zshrc; then
    add_source_to_zshrc "$file_to_source"
fi

# Update locate database
sudo updatedb

# Cleanup unused packages 

# Converts https to ssh
if [ -z $skip_convert ]; then
    if [ $skip_convert = false ]; then
        sed -i 's/https:\/\/github.com\//git@github.com:/g' /home/$USER/.dotfiles/config
        logging INFO "Converted from https to ssh"
    fi
else
    logging DEBUG "Skipping conversion from https to ssh"
fi

# TODO: Diff installed towards list 
logging WARNING "The following packages are not from the installer: $(echo ${unlisted_packages[@]})"
# Reboot if any changes were made
# Make this actually work
reboot=true
if [ "$reboot" = true ]; then
    echo ----------------------
    echo "Please reboot your PC"
    echo ----------------------
fi