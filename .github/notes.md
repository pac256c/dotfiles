# IMPORTANT
* STOP using :, just use ; for commands...
* type line number + G to go to a line (or 5j to go up 5, 5k to go right 5, etc.)
* change size of pane w/ ctrl + w + < or > or + or -  

# NVChad
* [nvchad link](https://nvchad.com/docs/quickstart/install/)
* using the nv file telescope
    * q to exit
    * a to create new file
    * d to delete file
    * r to rename file
    * note: qa or qa! exits all panes
    * to resize pane, e.g. :vertical resize -5
    * you can use ";" to enter command! (no need to press shift)
* basically, nvchad uses files in .config/nvim/lua to control stuff. the names are pretty self explanatory
  * autocmds.lua for things that run automatically
  * chadrc.lua for layouts/themes
  * mappings.lua for keybind changes
  * options.lua for additional option overrides
  * plugins/init.lua to enumerate plugins we want.
    * in nvchad these all have lazy=true set by default & will only be loaded on a specific event which you have to program.
    * need to program trigger to start the plugin or set lazy=false explicitly
      * example triggers cmd, ft, keys, or event
    * lazy.nvim automatically installs from github
  * can add plugins to the table returned in init.lua
* for languages we want to recognize, do these things:
  * in plugins/init.lua, add to ensure_installed list for treesitter. this ensures proper syntax highlighting / errors etc.
  * follow directions in https://nvchad.com/docs/config/lsp
  * check :help lspconfig-all to see if lsp for our language is there.
  * in $XDG_CONFIG_HOME/nvim/lua/configs/lspconfig.lua add to the server list.
  * run :MasonInstall + server name

# TMux
* changes to tmux
  * tmux leader is now ctrl + s
  * navigate panes w/ ctrl + hjkl
  * install tpm plugins w/ leader + I
  * reload tmux.conf with leader + r
  * create new window: leader + c
  * switch window: leader + number, OR just switch to next window using leader + n / leader + p, or leader + w to do this visually.
  * rename window: leader + ,
  * note: in tmux terminal, you can scroll up, highlight text and immediately copy. if you want, you can also hold shift to make this act like a normal terminal. to paste into the terminal, you can just use ctrl + v
  * tmux will continually save session. can restore on system restart just by calling "tmux"

> [!WARNING] 
> tmux continuum didn't work, not sure why.
