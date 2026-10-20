# Things to add
* atuin
* notetaking app
* whitakers words
* xfce
* unified task manager with visualizations disk management and stuff
* smth for internet, bluetooth, device management too?
* simple photo viewer & media player, or if yazi works thn tht
* snipping tool
* anti virus that works / cleaner app
* better solitaire / games that look nice
* wine/proton
* proton vpn / pass / drive
* application shortcuts - .desktop in .local/share/applications or yazi
* news feed & weather, maybe on toolbar

# Popup/nvim stuff - if we are in an nvim session
* nvim scrollbar - maybe petertriho/nvim-scrollbar
* images in nvim? maybe good for markdown stuff..
* can just drag panes dummy..
* tkdiff as a popup
* notes as a popup & maybe integrated with onenote if i can backwards engineer that
* make :e autopaste the path of the open file? 
* maybe some kind of repl/debugger thing that can execute files & output in a new pane below
  * would require dependencies...

# Yazi/kitty stuff
* update open shortcuts to use new programs
* already works as a simple photo viewer, but maybe make right arrow maximize it?
* maybe i can use as a simple video/media player?
* maybe i can fully view pdfs and other files in yazi?
* maybe i can use FUSE to go into archives/manipulate files
* maybe i can have another g + <> shortcut for applications?
* extension to show ground truth git/p4 depos, history/diffs/checkout

# AI stuff
* could i make claude use tui?
* could i use gemini + notebooks/stuff in a tui, maybe combined with a free agent for other stuff?
* organize / save conversations, handle multiple instances?
* maybe integrate w/ notes or something

# Cleaning up program installs to use package managers
* DONE: use yay to install everything, removed extra pacman step, combined lists into one packages.txt (gitfind.sh->manfind.sh, gitlist.txt->manlist.txt)
* DONE: dotfiles push/pull use conda-first-then-pacman; push regenerates packages.txt
* DONE: removed conda from this Arch achine (now global yay/pacman only); local/ flow kept for other machines
* DONE: .zshenv only adds PATH entries for directories that exist
* DONE: sync.sh scripts warn about stray dotfiles (with optional exit)

try to open my wsl for ssh from other computers?
could try to use tailnet-cli (instead of hamachi) 
 * winget install Tailscale.Tailscale
