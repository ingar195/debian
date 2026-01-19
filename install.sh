source functions.sh

check_git_status

if [[ -n "$SUDO_USER" || -n "$SUDO_UID" ]]; then
    logging ERROR "You are not allowed to run this script as sudo, exiting in 5 sec"
    sleep 5
    exit 1
fi

if [ -z "$(git config user.email)" ]; then
    read -p "Type your git email:  " git_email
    git config --global user.email "$git_email"
    
fi
if [ -z "$(git config user.name)" ]; then
    read -p "Type your git Full name:  " git_name
    git config --global user.name "$git_name"
fi

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF


echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(. /etc/os-release && echo "$VERSION_CODENAME") contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null
wget -q -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor &>/dev/null

sudo dpkg --configure -a
sudo apt update 2>/dev/null
sudo apt upgrade -y
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


if [ "$(echo $SHELL)" != "/usr/bin/zsh" ]; then
    logging INFO "Setting shell"
    sudo chsh -s /usr/bin/zsh $USER
fi

if [ ! -f $HOME/.oh-my-zsh/README.md ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
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