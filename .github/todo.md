* this will work for 64-bit ubuntu. changes needed for archlinux/64/32 bit
* create version for local install
* test git cloning
* make zshrc warn user about dotfiles?
* tmux resurrect + continuum + nvim AutoSession (plugins + autocmds.lua) not working
* autocmds.lua naming of unsaved files not really working..
* install languages for repl function
* add whitakers words
* maybe make :e autopaste the path of the open file?
* replace some of these installs with webinstall.dev versions (no package manager needed)
* some kind of file explorer i like to use. should include things like disk management
* some kind of window manager - maybe xfce seems good?
* have rifle.conf now, can use "o" to open stuff. set rifle.conf for o to use desired tools
* some kind of unified task manager with visualizations and stuff
* simple photo viewer, media player (maybe vlc?) 
* something like snipping tool
* some kind of anti virus that works
* some kind of cleaner application?
* better solitaire / games that kinda look nice
* wine/proton
* also will need to install proton applications vpn / pass / drive?
* rar/7z/etc to open more advanced archives, allow opening in file explorer too (all archive types could be nice..) 
  * or maybe something like overloading cd to cd into them on the command line?
  * maybe use "o" alias to unzip/untar/etc. to /tmp/... and cd in, or use FUSE?
  * already installed sevenzip actually in linuxbrew.
* figure out how to make applications links for app menu for artcraft-launcher, zen browser, etc. in xfce
* can just add .desktop shortcuts for these in .local/share/applications - but im not sure if this will work in xfce..
* use arch for wsl. lets nuke wsl and re-install arch?
* also, lets try to open my wsl for ssh from other computers?
* maybe add update script that says how to update stuff
* find out how to use yazi for archives, bulk rename, general usage.
* will want to convert all of these downloads to use package managers s.t. they are upgradable
  * linuxbrew can be installed to .local - thats at least helpful. cargo can too.
* i think the next update for this script (after typescript repl) will be an option for
   local install or package installer for each of these (whatever works) + update script for other stuff
   like git pulls, cargo/wget/curl if i need those...
* some kind of news feed, weather. maybe on the toolbar?
* might be nice to have nvim use transparent background / match yazi & vscode themes?
* write yazi lua extension to show "ground truth" git/p4 depos, hopefully could still view history/diffs/checkout.
* will also want to update yazi toml after installing all of the knock-off programs for word,excel,...


my current setup.sh script (after the initial pieces of code that delete dotfiles and update xdg directories) consists of a list of programs and commands to install them. i want to create a new, more interactive version of this script which contains a sort of list of all programs + methods to install them (plus maybe the zsh/bash code to install for that method). it should loop through the list, ask the user if they want to install, and depending on script priorities/inputs chooses a method, installs, and returns to the user. some extensions: maybe list ways of updating these programs too. the script hould be human-readable and easy to add new programs with tags, etc. can you draft a script that would work like this? for now, just echo the name of the program and install method instead of actually installing anything. 

