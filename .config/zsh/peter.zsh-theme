# peter_new.zsh-theme - standalone version (no oh-my-zsh dependency)

# These were previously provided by oh-my-zsh:
autoload -U colors && colors   # defines $fg, $fg_bold, $reset_color, etc.
setopt prompt_subst            # expand $(...) and $var inside PROMPT/RPROMPT

# ls coloring (previously set up by oh-my-zsh's lib/theme-and-appearance.zsh).
# dircolors colors file types (directories, links, ...) as well as
# permission-based highlighting (su/sg = setuid/setgid, tw = sticky+other
# writable, ow = other writable, ...).
if [[ "$DISABLE_LS_COLORS" != true ]]; then
  export LSCOLORS="Gxfxcxdxbxegedabagacad"   # BSD ls
  if [[ -z "$LS_COLORS" ]]; then             # GNU ls
    if (( $+commands[dircolors] )); then
      [[ -f "$HOME/.dircolors" ]] \
        && source <(dircolors -b "$HOME/.dircolors") \
        || source <(dircolors -b)
    else
      export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
    fi
  fi

  # GNU ls only honors LS_COLORS with --color (BSD ls uses -G with LSCOLORS).
  if ls --color /dev/null &>/dev/null; then
    alias ls='ls --color=tty'
  elif ls -G /dev/null &>/dev/null; then
    alias ls='ls -G'
  fi
fi

# --- Git helpers ----------------------------------------------------------

function __git_prompt_git() {
  GIT_OPTIONAL_LOCKS=0 command git "$@"
}

# Absolute path to the repo root, or empty if not inside a repo.
function _peter_git_root() {
  __git_prompt_git rev-parse --show-toplevel 2>/dev/null
}

# Current branch name; falls back to an exact tag, then a short SHA.
function _peter_git_branch() {
  local ref
  if ref="$(__git_prompt_git symbolic-ref --short HEAD 2>/dev/null)"; then
    echo "$ref"
    return
  fi
  if ref="$(__git_prompt_git describe --tags --exact-match HEAD 2>/dev/null)"; then
    echo "$ref"
    return
  fi
  ref="$(__git_prompt_git rev-parse --short HEAD 2>/dev/null)" && echo "$ref" || echo '?'
}

# One of: unstaged | uncommitted | clean
#   unstaged    - tracked files modified in the working tree (or untracked files)
#   uncommitted - changes staged but not yet committed
#   clean       - nothing staged or modified
function _peter_git_state() {
  local line x y has_unstaged=0 has_staged=0
  local -a lines
  lines=("${(@f)$(__git_prompt_git status --porcelain 2>/dev/null)}")
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    x="${line[1]}"
    y="${line[2]}"
    if [[ "$x" == '?' ]]; then     # untracked
      has_unstaged=1
    else
      [[ "$x" != ' ' ]] && has_staged=1     # staged change
      [[ "$y" != ' ' ]] && has_unstaged=1   # working-tree change
    fi
  done
  if (( has_unstaged )); then
    echo unstaged
  elif (( has_staged )); then
    echo uncommitted
  else
    echo clean
  fi
}

# --- Perforce -------------------------------------------------------------

# True when the cwd is inside the codeline directory ($STEM, trailing / ignored).
function _peter_p4_in_stem() {
  local stem="${STEM%/}"
  [[ "$PWD" == "$stem" || "$PWD" == "$stem"/* ]]
}

# We're in a p4 codeline only when all three vars are set and we're under $STEM.
# Outside $STEM we fall back to the normal prompt even if the vars remain set.
function _peter_p4_active() {
  [[ -n "$STEM" && -n "$SCMROOT" && -n "$DJ_CONTEXT" ]] || return 1
  _peter_p4_in_stem
}

# `p4 opened` is the query for open files, but it can be slow, so instead of
# running it on every prompt we only refresh it when a p4 command has just run
# (detected by the preexec hook below), when we first enter a codeline, or when
# the codeline changes. The result is cached in _PETER_P4_STATE; the globals
# persist because these hooks run in the main shell, unlike the PROMPT command
# substitution which runs in a subshell.
#
#   ""            - unknown / not checked yet
#   clean         - nothing open                          -> green triangle
#   open-default  - files open in the default changelist  -> red triangle
#   open-other    - files open, none in the default CL    -> yellow triangle
typeset -g _PETER_P4_STATE=""
typeset -g _PETER_P4_CONTEXT=""      # codeline the cached state belongs to
typeset -g _PETER_P4_NEEDS_CHECK=0   # set by preexec when a p4 command runs

# preexec: flag that a p4 command is about to run, so the next precmd refreshes.
function _peter_p4_preexec() {
  _peter_p4_active || return
  local word
  for word in ${(z)1}; do
    if [[ "$word" == p4 || "$word" == */p4 ]]; then
      _PETER_P4_NEEDS_CHECK=1
      return
    fi
  done
}

function _peter_p4_precmd() {
  if ! _peter_p4_active; then
    _PETER_P4_STATE=""
    _PETER_P4_CONTEXT=""
    _PETER_P4_NEEDS_CHECK=0
    return
  fi

  local context="$STEM|$SCMROOT|$DJ_CONTEXT"
  # Nothing to do unless a p4 command ran, we've never checked, or the codeline
  # changed.
  if (( ! _PETER_P4_NEEDS_CHECK )) &&
     [[ -n "$_PETER_P4_STATE" && "$context" == "$_PETER_P4_CONTEXT" ]]; then
    return
  fi
  _PETER_P4_NEEDS_CHECK=0

  _PETER_P4_CONTEXT="$context"          # don't retry until something changes
  local opened
  if ! opened="$(command p4 opened 2>/dev/null)"; then
    return                              # p4 failed; keep the last known color
  fi
  if [[ -z "${opened//[[:space:]]/}" || "$opened" == *"no files opened"* ]]; then
    _PETER_P4_STATE=clean
  elif [[ "$opened" == *"default change"* ]]; then
    _PETER_P4_STATE=open-default
  else
    _PETER_P4_STATE=open-other
  fi
}

autoload -Uz add-zsh-hook
(( ${precmd_functions[(I)_peter_p4_precmd]} )) || add-zsh-hook precmd _peter_p4_precmd
(( ${preexec_functions[(I)_peter_p4_preexec]} )) || add-zsh-hook preexec _peter_p4_preexec

# --- Prompt ---------------------------------------------------------------

# Prints the whole prompt:
#   in a git repo:          "<path> <repo>:<branch> <status triangle> "
#   inside a p4 codeline:   "<path rel to $STEM> <scmroot>:<$DJ_CONTEXT> (<$STEM>) <status triangle> "
#   not in a repo/codeline: "<full path> <status triangle> "
function _peter_prompt_segment() {
  local reset path_c repo_c branch_c bootinfo_c
  local dot_unstaged dot_uncommitted dot_clean
  if [[ "$TERM" != "dumb" && "$DISABLE_LS_COLORS" != true ]]; then
    reset=$'%{\e[0m%}'
    path_c=$'%{\e[38;5;116m%}'           # pastel cyan
    repo_c=$'%{\e[38;5;216m%}'           # pastel orange (peach)
    branch_c=$'%{\e[38;5;218m%}'         # pastel pink
    bootinfo_c=$'%{\e[38;5;183m%}'       # pastel purple (mauve)
    dot_unstaged=$'%{\e[38;5;211m%}'     # pastel red
    dot_uncommitted=$'%{\e[38;5;223m%}'  # pastel yellow
    dot_clean=$'%{\e[38;5;120m%}'        # bright eye-catching green
  fi

  local full_path="${PWD/#$HOME/~}"

  # Perforce codeline: active only when STEM, SCMROOT and DJ_CONTEXT are all set
  # and the cwd is inside $STEM (otherwise fall back to the normal prompt).
  # Paths are relative to $STEM; SCMROOT's basename plays the role of the repo
  # name, DJ_CONTEXT the branch, and STEM's basename takes the place of the
  # status parens.
  if _peter_p4_active; then
    local p4_rel="${PWD#${STEM%/}}"
    local p4_path="./${p4_rel#/}"
    local p4_dot=$dot_clean
    case "$_PETER_P4_STATE" in
      open-default) p4_dot=$dot_unstaged ;;
      open-other)   p4_dot=$dot_uncommitted ;;
    esac
    print -n -- "${path_c}${p4_path}${reset} ${repo_c}[${SCMROOT:t}${reset}:${branch_c}${DJ_CONTEXT}]${reset} (${bootinfo_c}${STEM:t}${reset}) ${p4_dot}▶${reset} "
    return
  fi

  local root="$(_peter_git_root)"

  if [[ -z "$root" ]]; then
    print -n -- "${path_c}${full_path}${reset} ${dot_clean}▶${reset} "
    return
  fi

  local rel="${${$(__git_prompt_git rev-parse --show-prefix 2>/dev/null)}%/}"
  local repo="${root:t}"
  local branch="$(_peter_git_branch)"

  local dot_color
  case "$(_peter_git_state)" in
    unstaged)    dot_color=$dot_unstaged ;;
    uncommitted) dot_color=$dot_uncommitted ;;
    *)           dot_color=$dot_clean ;;
  esac

  print -n -- "${path_c}./${rel}${reset} ${repo_c}[${repo}${reset}:${branch_c}${branch}]${reset} ${dot_color}▶${reset} "
}

# --- Commands -------------------------------------------------------------

# `home` jumps to the root of whatever the prompt is currently showing:
#   p4 prompt   -> the codeline root ($STEM)
#   git prompt  -> the repository root
#   otherwise   -> the home directory
function home() {
  if _peter_p4_active; then
    cd "${STEM%/}"
    return
  fi
  local root
  root="$(_peter_git_root)"
  if [[ -n "$root" ]]; then
    cd "$root"
  else
    cd ~
  fi
}

PROMPT='$(_peter_prompt_segment)'
RPROMPT=''
