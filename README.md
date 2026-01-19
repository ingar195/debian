# Debian
**This is still work in progress**

## Description 
Based on [Github](https://github.com/ingar195/Arch)


Script to prepare debian after install

## Dotfiles
Dotfiles is what we have named the git bare repo we use for backing up OS settings and non-sensitive files.  
These are stored in a GitHub repo like [this](https://github.com/ingar195/dotfiles).


## Usage
When installing, you have a selection of arguments. They can be used all together or one at a time.
Arguments:
* `sh install.sh [-s -d -c]`
* `-s` skips converting the dotfiles repo to SSH (mostly used for testing) 
* `-d` enables debug to console log 
* `-c` includes installation of the sec tools


## Features
Here are some of the features:  
* Updates the PC
* Sets up git username and email
* Installs all packages from the packages file
    * Supports https links to deb files
* Configures:
    * zsh
        * aliases 
        * theme
        * omz
    * 

* Aliases and commands:
    - `dotfiles`    Is an alias for using the dotfiles repo that gets initialized or downloaded during installation.
    - `dotp`        Alias for quickly committing and pushing all changes in files already committed 
    - `rs`          Alias for using the rsync command with our preferred options
    - `cansetup`    Alias for setting up can-bus to be used with can-utils
    - `wg`          Alias for connecting with WireGuard to the file `/home/$USER/.config/wireguard/wg0.conf`
    - `wgd`         Alias for disconnecting WireGuard
    - `wgh`         Alias for connecting with WireGuard to the file `/home/$USER/.config/wireguard/wg1.conf`
    - `wgd`         Alias for disconnecting WireGuard
    - `lll`         Alias for tree view
    - `py`          Runs Python3 commands
    - `python`      Runs Python3 commands
    - `cpu`         Used for checking current core clock per thread
    - `uninstall`   Removes installed programs
    - `update`      Updates the script and the PC