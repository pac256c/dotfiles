#!/usr/bin/env bash
# ============================================================================
# sync.sh - interactive program sync for Ubuntu and Arch
#
# A registry of programs, each with one or more install methods. Every method
# belongs to a kind that says *how* it installs:
#
#   UBUNTU   apt (Debian/Ubuntu package manager)
#   ARCH     pacman / yay (Arch package managers)
#   LOCAL    no-distro install: installer script, tarball, cargo/pip/brew/npm
#   SCRATCH  build from source in the working tree
#
# Kinds imply priority: distro (UBUNTU/ARCH) first, then LOCAL, then
# SCRATCH. You pass a kind (lowercase) as the starting point; it and the
# lower priority kinds become eligible:
#
#   --kind ubuntu   -> UBUNTU + LOCAL + SCRATCH
#   --kind arch     -> ARCH   + LOCAL + SCRATCH
#   --kind local    -> LOCAL  + SCRATCH
#   --kind scratch  -> SCRATCH
#
# Progress is tracked in $XDG_STATE_HOME/sync/ (installed.state and
# updated.state), so a re-run resumes where it left off. A failing command
# stops the script immediately. Commands are executed by default, each in a
# child shell on the terminal so installers can prompt; pass --echo/-e to
# preview them without running anything and without writing state.
#
# `update` follows the methods recorded in installed.state: the package
# managers (apt, pacman, yay, brew) are upgraded once each via a catch-all,
# while programs with their own updater (rustup, cargo, pip, npm, git) update
# individually.
#
# Run this as your normal user, NOT with sudo: LOCAL/SCRATCH installers target
# the invoking user's $HOME, while distro package managers self-elevate via a
# $SUDO prefix (which becomes empty automatically when already root). Starting
# with --kind ubuntu/arch runs "sudo -v" up front and aborts if it fails.
#
# Before installing or updating it does a pre-flight in $HOME: it warns about
# stray dotfiles (anything other than .config/.local/.cache/.github) and asks to
# continue, and it renames capitalized XDG user directories to lowercase before
# running "xdg-user-dirs-update --force". It then runs the installs/updates from
# /tmp and, on exit or ctrl+d/Ctrl-C, returns to the directory you launched it
# from. Under --echo the pre-flight only reports what it would do.
#
# Output is colored when stdout is a terminal; set NO_COLOR to disable.
#
# The program and method list lives in registry.sh next to this script; edit
# that file to add or change programs.
#
# Commands run under bash until zsh is installed; from then on every command is
# run under zsh, which sources your .zshenv and .zshrc, so the rest of the
# install/update uses your zsh environment, aliases and functions.
#
# Usage:
#   ./sync.sh -k ubuntu [options]          # install (default)
#   ./sync.sh -u -k arch [options]         # update
#   ./sync.sh -n -k local                  # next pending step only
#   ./sync.sh --list
#     (--list marks each program: ✓ installed, ↑ updated in the current run)
#
# Options:
#   -k, --kind C      REQUIRED for install/update: ubuntu, arch, local, scratch
#   -u, --update      update instead of install (install is the default)
#   -p, --program a,b only these exact program names
#   -n, --next        run only the next not-yet-done install/update, then stop
#   -e, --echo        print commands without executing or writing state
#   -h, --help        show this help
# ============================================================================

set -uo pipefail

# ----------------------------------------------------------------------------
# Registry storage
# ----------------------------------------------------------------------------
declare -A M_KIND=()       # "name:method" -> kind
declare -A M_INSTALL=()   # "name:method" -> install command
declare -A M_UPDATE=()    # "name:kind:method" -> update command (optional)
declare -a PROGRAMS=()    # registry order
declare -a METHOD_KEYS=() # every "name:method" key, in definition order

declare -A MANAGER_UPDATE=() # method -> catch-all update command
declare -A MANAGER_KIND=()    # method -> kind
declare -a MANAGER_KEYS=()   # manager methods, in definition order

ALLOWED_KINDS="UBUNTU ARCH LOCAL SCRATCH"

# add_program NAME
add_program() {
  PROGRAMS+=("$1")
}

# add_install_method NAME KIND METHOD [COMMAND]
#   COMMAND is a single quoted string, or omit it and supply a heredoc:
#   add_install_method NAME KIND METHOD <<'CMD' ... CMD
add_install_method() {
  local name="$1" kind="$2" method="$3"
  local key="$name:$method" cmd
  if [[ $# -ge 4 ]]; then cmd="$4"; else cmd="$(cat)"; fi
  M_KIND["$key"]="$kind"
  M_INSTALL["$key"]="$cmd"
  METHOD_KEYS+=("$key")
}

# add_update_method NAME KIND METHOD [COMMAND]
#   The kind ties the update to the same-kind install method, so a program
#   installed via a package manager (and covered by that manager's catch-all)
#   never falls through to a different-kind update command. COMMAND is a single
#   quoted string, or omit it and supply a heredoc.
add_update_method() {
  local name="$1" kind="$2" method="$3"
  local key="$name:$kind:$method" cmd
  if [[ $# -ge 4 ]]; then cmd="$4"; else cmd="$(cat)"; fi
  M_UPDATE["$key"]="$cmd"
}

# add_manager_update METHOD KIND [COMMAND]
#   A catch-all update for a package manager, run once per update.
#   COMMAND is a single quoted string, or omit it and supply a heredoc.
add_manager_update() {
  local method="$1" kind="$2" cmd
  if [[ $# -ge 3 ]]; then cmd="$3"; else cmd="$(cat)"; fi
  MANAGER_KIND["$method"]="$kind"
  MANAGER_UPDATE["$method"]="$cmd"
  MANAGER_KEYS+=("$method")
}

# ----------------------------------------------------------------------------
# Registry - the program/method list lives in registry.sh, sourced here
# ----------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/registry.sh" ]]; then
  source "$SCRIPT_DIR/registry.sh"
else
  printf 'error: registry.sh not found next to %s\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

# ============================================================================
# Driver
# ============================================================================

MODE="install"
KIND=""
PROGRAM_FILTER=""
NEXT=0
ASSUME_YES=1
RUN=1
START_DIR=""

# Interpreter for install/update commands. Starts as bash and switches to zsh
# as soon as zsh is available (i.e. once it has been installed), so the rest of
# the programs install under the user's zsh with their config sourced.
RUN_SHELL="bash"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sync"
INSTALL_STATE="$STATE_DIR/installed.state"
UPDATE_STATE="$STATE_DIR/updated.state"

INSTALLED=0
SKIPPED=0

# --- privilege --------------------------------------------------------------

# Commands carry a $SUDO prefix so they work whether launched as a user
# (SUDO=sudo) or as root (SUDO="", no redundant sudo). local/scratch installers
# still run as the invoking user because we never require whole-script sudo.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi
export SUDO

# --- colors -----------------------------------------------------------------

# SGR parameter strings for c(); c() wraps them as ESC[<params>m.
BOLD=1
DIM=2
RED=31
BRED='1;31'
GREEN=32
ORANGE='38;5;208'
YELLOW=33
CYAN=36

USE_COLOR=0

# usage() prints the banner comment at the top of this file.
usage() {
  sed -n '2,68p' "$0" | sed 's/^# \{0,1\}//'
}

# kind_code KIND -> SGR parameters for that kind's color
kind_code() {
  case "$1" in
    UBUNTU)  printf '38;5;208' ;;   # orange
    ARCH)    printf '38;5;39'  ;;   # blue
    LOCAL)   printf '38;5;34'  ;;   # green
    SCRATCH) printf '38;5;212' ;;   # pink
    *)       printf '0'        ;;
  esac
}

# c CODE TEXT -> TEXT wrapped in CODE, or plain when colors are off
c() {
  if [[ $USE_COLOR -eq 1 ]]; then
    printf '\033[%sm%s\033[0m' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

# kind_label KIND -> kind name in its color
kind_label() { c "$(kind_code "$1")" "$1"; }

# prog_header NAME -> bold "=== NAME ===" block header (with leading blank line)
prog_header() { printf '\n%s\n' "$(c "$BOLD" "=== $1 ===")"; }

# method_kind KEY -> "method (kind)" with a cyan method and colored kind
method_kind() {
  printf '%s (%s)' "$(c "$CYAN" "${1#*:}")" "$(kind_label "${M_KIND[$1]}")"
}

# setup_colors -> colorize only when stdout is a real terminal and the
# environment doesn't ask us not to (NO_COLOR / dumb terminal).
setup_colors() {
  if [[ -z "${NO_COLOR:-}" && -t 1 && "${TERM:-}" != "dumb" ]]; then
    USE_COLOR=1
  else
    USE_COLOR=0
  fi
}

# prompt_read VAR "prompt" -> read a line into VAR; a ctrl+d (EOF) aborts the
# whole run cleanly instead of being mistaken for an empty answer.
prompt_read() {
  local __var="$1" __prompt="$2" __answer
  if ! read -r -p "$__prompt" __answer; then
    printf '\n%s\n' "$(c "$YELLOW" 'input closed (ctrl+d); aborting')"
    exit 130
  fi
  printf -v "$__var" '%s' "$__answer"
}

# in_list NEEDLE "a,b,c"
in_list() {
  local needle="$1" csv="$2" item
  [[ -n "$csv" ]] || return 1
  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# validate_kind "A,B" -> 0 if every entry is a known kind
validate_kind() {
  local csv="$1" c
  IFS=',' read -ra kinds <<< "$csv"
  for c in "${kinds[@]}"; do
    in_list "${c^^}" "${ALLOWED_KINDS// /,}" || return 1
  done
  return 0
}

# kind_rank KIND -> 1 (distro), 2 (local), 3 (scratch)
kind_rank() {
  case "$1" in
    UBUNTU|ARCH) echo 1 ;;
    LOCAL) echo 2 ;;
    SCRATCH) echo 3 ;;
    *) echo 99 ;;
  esac
}

# eligible_kinds START -> kinds at or below START's rank.
# The starting kind also pins the distro; LOCAL/SCRATCH skip the distro tier.
eligible_kinds() {
  case "$1" in
    UBUNTU) printf 'UBUNTU,LOCAL,SCRATCH' ;;
    ARCH) printf 'ARCH,LOCAL,SCRATCH' ;;
    LOCAL) printf 'LOCAL,SCRATCH' ;;
    SCRATCH) printf 'SCRATCH' ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--update) MODE="update" ;;
      -k|--kind) KIND="${2:-}"; KIND="${KIND^^}"; shift ;;
      -p|--program) PROGRAM_FILTER="${2:-}"; shift ;;
      -n|--next) NEXT=1 ;;
      -e|--echo) RUN=0; ASSUME_YES=0 ;;
      --list) MODE="list" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done
}

# wanted NAME -> 0 if the --program filter selects it
wanted() {
  local prog="$1"
  if [[ -n "$PROGRAM_FILTER" ]] && ! in_list "$prog" "$PROGRAM_FILTER"; then
    return 1
  fi
  return 0
}

# methods_for NAME -> "rank<TAB>name:method" for eligible methods, best first
methods_for() {
  local prog="$1" kinds key rank
  kinds="$(eligible_kinds "$KIND")"
  for key in "${METHOD_KEYS[@]}"; do
    [[ "${key%%:*}" == "$prog" ]] || continue
    in_list "${M_KIND[$key]}" "$kinds" || continue
    rank="$(kind_rank "${M_KIND[$key]}")"
    printf '%s\t%s\n' "$rank" "$key"
  done | sort -n -k1,1
}

# manager_eligible METHOD -> 0 if the manager's kind fits --kind
manager_eligible() {
  in_list "${MANAGER_KIND[$1]:-}" "$(eligible_kinds "$KIND")"
}

# manager_key METHOD -> updated.state target for a manager update
manager_key() { printf '@%s' "$1"; }

# managers_used -> managers used by wanted+installed programs, canonical order
managers_used() {
  local mgr prog method
  for mgr in "${MANAGER_KEYS[@]}"; do
    manager_eligible "$mgr" || continue
    for prog in "${PROGRAMS[@]}"; do
      wanted "$prog" || continue
      is_installed "$prog" || continue
      method="$(state_field "$INSTALL_STATE" "$prog" method)"
      if [[ "$method" == "$mgr" ]]; then
        printf '%s\n' "$mgr"
        break
      fi
    done
  done
}

# program_update NAME -> 0 and prints "name:kind:method" when the recorded
# install (method+kind) has a per-program update command eligible for --kind
program_update() {
  local prog="$1" method kind key
  method="$(state_field "$INSTALL_STATE" "$prog" method)"
  [[ -n "$method" ]] || return 1
  kind="$(installed_kind "$prog")"
  [[ -n "$kind" ]] || return 1
  key="$prog:$kind:$method"
  [[ -n "${M_UPDATE[$key]:-}" ]] || return 1
  in_list "$kind" "$(eligible_kinds "$KIND")" || return 1
  printf '%s\n' "$key"
}

# kinds_for NAME -> comma list of kinds, canonical order
kinds_for() {
  local prog="$1" key c seen=""
  for c in UBUNTU ARCH LOCAL SCRATCH; do
    for key in "${METHOD_KEYS[@]}"; do
      [[ "${key%%:*}" == "$prog" ]] || continue
      if [[ "${M_KIND[$key]}" == "$c" ]]; then
        seen="${seen:+$seen,}$c"
        break
      fi
    done
  done
  printf '%s' "$seen"
}

# --- state files ------------------------------------------------------------

state_dir_init() {
  mkdir -p "$STATE_DIR"
}

# state_has FILE NAME -> 0 if NAME has any entry in FILE
state_has() {
  local file="$1" prog="$2" st p m f4 f5
  [[ -f "$file" ]] || return 1
  while IFS=$'\t' read -r st p m f4 f5; do
    [[ "$p" == "$prog" ]] && return 0
  done < "$file"
  return 1
}

# state_field FILE NAME FIELD(status|method|kind) -> last matching value.
# installed.state rows are "status name method kind ts"; older rows and
# updated.state rows are "status name method ts" (kind is then empty).
state_field() {
  local file="$1" prog="$2" which="$3" st p m f4 f5 result=""
  [[ -f "$file" ]] || return 1
  while IFS=$'\t' read -r st p m f4 f5; do
    if [[ "$p" == "$prog" ]]; then
      case "$which" in
        status) result="$st" ;;
        method) result="$m" ;;
        kind)   [[ -n "$f5" ]] && result="$f4" ;;
      esac
    fi
  done < "$file"
  printf '%s' "$result"
}

# is_installed NAME -> 0 if the latest status for NAME is "installed"
is_installed() {
  [[ "$(state_field "$INSTALL_STATE" "$1" status)" == "installed" ]]
}

# installed_kind NAME -> the kind NAME was installed with, derived from the
# install method when the recorded row predates kind tracking.
installed_kind() {
  local prog="$1" k m
  k="$(state_field "$INSTALL_STATE" "$prog" kind)"
  if [[ -z "$k" ]]; then
    m="$(state_field "$INSTALL_STATE" "$prog" method)"
    k="${M_KIND[$prog:$m]:-}"
  fi
  printf '%s' "$k"
}

# record_state FILE STATUS NAME METHOD [KIND] -> replace NAME's line with a new
# one; KIND is only written when given (installed.state).
record_state() {
  local file="$1" status="$2" prog="$3" method="$4" kind="${5:-}"
  state_dir_init
  local tmp; tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    local st p m f4 f5 ek ets
    while IFS=$'\t' read -r st p m f4 f5; do
      [[ "$p" == "$prog" ]] && continue
      if [[ -n "$f5" ]]; then ek="$f4"; ets="$f5"; else ek=""; ets="$f4"; fi
      if [[ -n "$ek" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$p" "$m" "$ek" "$ets"
      else
        printf '%s\t%s\t%s\t%s\n' "$st" "$p" "$m" "$ets"
      fi
    done < "$file" > "$tmp"
  fi
  if [[ -n "$kind" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$status" "$prog" "$method" "$kind" "$(date +%Y-%m-%dT%H:%M:%S)" >> "$tmp"
  else
    printf '%s\t%s\t%s\t%s\n' \
      "$status" "$prog" "$method" "$(date +%Y-%m-%dT%H:%M:%S)" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

record_installed() { record_state "$INSTALL_STATE" installed "$1" "$2" "$3"; }
record_failed()    { record_state "$INSTALL_STATE" failed    "$1" "$2" "$3"; }
record_updated()   { record_state "$UPDATE_STATE"  updated   "$1" "$2"; }

# update_pending -> 0 if a used manager or updated program is still pending
update_pending() {
  local prog mgr
  for mgr in $(managers_used); do
    state_has "$UPDATE_STATE" "$(manager_key "$mgr")" || return 0
  done
  for prog in "${PROGRAMS[@]}"; do
    wanted "$prog" || continue
    is_installed "$prog" || continue
    program_update "$prog" >/dev/null || continue
    state_has "$UPDATE_STATE" "$prog" && continue
    return 0
  done
  return 1
}

# print_cmd "command" -> first line prefixed with "$ ", rest hanging-indented
print_cmd() {
  local sub="" cmd line first=1
  [[ -n "$SUDO" ]] && sub="$SUDO "
  cmd="${1//\$SUDO /$sub}"
  while IFS= read -r line; do
    if [[ $first -eq 1 ]]; then
      printf '    %s %s\n' "$(c "$GREEN" '$')" "$line"
      first=0
    else
      printf '      %s\n' "$line"
    fi
  done <<< "$cmd"
}

# use_zsh_if_available -> once zsh exists (it has just been installed, or was
# already present), switch the command interpreter from bash to zsh. Announced
# once. run_cmd sources the user's .zshenv and .zshrc by hand so environment,
# aliases and functions are available to the install commands.
use_zsh_if_available() {
  [[ "$RUN_SHELL" == "zsh" ]] && return 0
  command -v zsh >/dev/null 2>&1 || return 0
  RUN_SHELL="zsh"
  printf '  %s\n' "$(c "$DIM" 'zsh available: running the rest of the commands under zsh')"
}

# run_cmd "command" -> print it, then (unless in --echo mode) hand it to a
# child shell on the terminal (set -e, stdin from /dev/tty) so installers can
# prompt the user. Runs under bash until zsh is available, then under zsh with
# the user's .zshenv and .zshrc sourced.
run_cmd() {
  local cmd="$1"
  [[ -n "$cmd" ]] || { printf '    (no command)\n'; return 0; }
  print_cmd "$cmd"
  [[ $RUN -eq 1 ]] || return 0

  use_zsh_if_available

  local tmp rc
  tmp="$(mktemp)"
  if [[ "$RUN_SHELL" == "zsh" ]]; then
    {
      # zsh normally sources .zshenv at startup, but this .zshenv exports
      # ZDOTDIR, so the child looks for $ZDOTDIR/.zshenv (usually nonexistent)
      # and skips it. Source .zshenv and .zshrc ourselves to be sure. set -e
      # comes after, so a noisy rc file can't abort the command.
      printf '%s\n' 'zdot="${ZDOTDIR:-$HOME}"'
      printf '%s\n' 'zshenv="$zdot/.zshenv"'
      printf '%s\n' '[[ -f "$zshenv" ]] || zshenv="$HOME/.zshenv"'
      printf '%s\n' '[[ -f "$zshenv" ]] && source "$zshenv"'
      printf '%s\n' 'zdot="${ZDOTDIR:-$HOME}"'
      printf '%s\n' '[[ -f "$zdot/.zshrc" ]] && source "$zdot/.zshrc"'
      printf 'set -e\n'
      printf '%s\n' "$cmd"
    } > "$tmp"
  else
    { printf 'set -e\n'; printf '%s\n' "$cmd"; } > "$tmp"
  fi
  if [[ -t 0 ]]; then
    "$RUN_SHELL" "$tmp"
  elif { exec 3</dev/tty; } 2>/dev/null; then
    "$RUN_SHELL" "$tmp" <&3
    exec 3<&-
  else
    "$RUN_SHELL" "$tmp"
  fi
  rc=$?
  rm -f "$tmp"
  return $rc
}

# update_done NAME -> 0 if NAME was updated in the current run. A program with
# its own (kind-matching) update method uses its own row; a manager-installed
# program without one is covered by that manager's catch-all row.
update_done() {
  local prog="$1" method kind
  is_installed "$prog" || return 1
  method="$(state_field "$INSTALL_STATE" "$prog" method)"
  kind="$(installed_kind "$prog")"
  if [[ -n "$method" && -n "$kind" && -n "${M_UPDATE[$prog:$kind:$method]:-}" ]]; then
    state_has "$UPDATE_STATE" "$prog"
    return
  fi
  if [[ -n "$method" && -n "${MANAGER_UPDATE[$method]:-}" ]]; then
    state_has "$UPDATE_STATE" "$(manager_key "$method")"
    return
  fi
  state_has "$UPDATE_STATE" "$prog"
}

# status_cell NAME -> fixed 3-column marker cell: a green ✓ when installed, an
# orange ↑ when updated in the current run, both, or a dim · when neither. The
# glyphs are multibyte, so pad by counting marks rather than printf width.
status_cell() {
  local out="" n=0 i
  if is_installed "$1"; then out+="$(c "$GREEN" '✓')"; n=$((n+1)); fi
  if update_done "$1"; then out+="$(c "$ORANGE" '↑')"; n=$((n+1)); fi
  if [[ $n -eq 0 ]]; then out="$(c "$DIM" '·')"; n=1; fi
  printf '%s' "$out"
  for ((i = n; i < 3; i++)); do printf ' '; done
}

list_programs() {
  local prog kinds c first hdr tags
  printf -v hdr '%-20s' "PROGRAM"
  printf '%s %s %s\n' "$(c "$BOLD" "STATUS")" "$(c "$BOLD" "$hdr")" "$(c "$BOLD" "KINDS")"
  printf '%s\n' "$(c "$DIM" '✓ installed  ↑ updated')"
  for prog in "${PROGRAMS[@]}"; do
    printf -v hdr '%-20s' "$prog"
    kinds="$(kinds_for "$prog")"
    tags=""
    first=1
    local -a parts=()
    IFS=',' read -ra parts <<< "$kinds"
    for c in "${parts[@]}"; do
      [[ $first -eq 1 ]] || tags+=","
      tags+="$(kind_label "$c")"
      first=0
    done
    printf '%s %s [%s]\n' "$(status_cell "$prog")" "$(c "$BOLD" "$hdr")" "$tags"
  done
}

# report_no_method NAME -> explain NAME has no method for the chosen kind, and
# list the methods it does offer.
report_no_method() {
  local prog="$1" key first=1
  prog_header "$prog"
  printf '  %s\n' "$(c "$YELLOW" "no method available for kind [${KIND,,}]")"
  printf '  available methods: '
  for key in "${METHOD_KEYS[@]}"; do
    [[ "${key%%:*}" == "$prog" ]] || continue
    [[ $first -eq 1 ]] || printf ', '
    method_kind "$key"
    first=0
  done
  printf '\n'
}

# install_one NAME -> 0 handled, 2 means "skip the rest of the run"
install_one() {
  local prog="$1"
  local -a rows=() keys=()
  mapfile -t rows < <(methods_for "$prog")
  if [[ ${#rows[@]} -eq 0 ]]; then
    report_no_method "$prog"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  local row k
  for row in "${rows[@]}"; do
    keys+=("${row#*$'\t'}")
  done

  local chosen="${keys[0]}"

  prog_header "$prog"

  local answer rc
  while :; do
    printf '  install via: %s\n' "$(method_kind "$chosen")"
    if [[ $ASSUME_YES -eq 1 ]]; then
      answer="y"
    else
      prompt_read answer "  Install $prog? [Y]es/[n]o/[m]ethod/[s]kip-rest: "
    fi
    case "${answer,,}" in
      ""|y|yes)
        printf '  %s install %s (%s)\n' "$(c "$DIM" '->')" "$prog" "${chosen#*:}"
        run_cmd "${M_INSTALL[$chosen]}"
        rc=$?
        if [[ $RUN -eq 1 ]]; then
          if [[ $rc -ne 0 ]]; then
            record_failed "$prog" "${chosen#*:}" "${M_KIND[$chosen]}"
            printf '  %s %s failed (exit %d); stopping.\n' \
              "$(c "$BRED" '!!')" "$prog" "$rc" >&2
            exit 1
          fi
          record_installed "$prog" "${chosen#*:}" "${M_KIND[$chosen]}"
        fi
        INSTALLED=$((INSTALLED + 1))
        return 0
        ;;
      n|no)
        printf '  %s skipped %s\n' "$(c "$YELLOW" '->')" "$prog"
        SKIPPED=$((SKIPPED + 1))
        return 0
        ;;
      m|method)
        printf '  methods:\n'
        local i=1
        for k in "${keys[@]}"; do
          printf '    %s) %s\n' "$(c "$CYAN" "$i")" "$(method_kind "$k")"
          i=$((i + 1))
        done
        prompt_read answer "  choose method number: "
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#keys[@]} )); then
          chosen="${keys[$((answer - 1))]}"
        else
          printf '  %s\n' "$(c "$RED" 'invalid selection')"
        fi
        ;;
      s|skip)
        return 2
        ;;
      *)
        printf '  %s\n' "$(c "$YELLOW" 'please answer y, n, m, or s')"
        ;;
    esac
  done
}

# update_manager METHOD -> run a package manager's catch-all update once
update_manager() {
  local method="$1"
  printf '  %s (%s):\n' "$(c "$CYAN" "$method")" "$(kind_label "${MANAGER_KIND[$method]}")"
  run_cmd "${MANAGER_UPDATE[$method]}"
  local rc=$?
  if [[ $RUN -eq 1 ]]; then
    if [[ $rc -ne 0 ]]; then
      printf '  %s %s update failed (exit %d); stopping.\n' \
        "$(c "$BRED" '!!')" "$method" "$rc" >&2
      exit 1
    fi
    record_updated "$(manager_key "$method")" "$method"
  fi
  return 0
}

# update_one NAME -> 0 if a per-program update ran, 1 if none applies
update_one() {
  local prog="$1" key kind method
  key="$(program_update "$prog")" || return 1
  kind="${key#*:}"; kind="${kind%%:*}"
  method="${key##*:}"

  prog_header "$prog"
  printf '  update via %s (%s):\n' "$(c "$CYAN" "$method")" "$(kind_label "$kind")"
  run_cmd "${M_UPDATE[$key]}"
  local rc=$?
  if [[ $RUN -eq 1 ]]; then
    if [[ $rc -ne 0 ]]; then
      printf '  %s %s update failed (exit %d); stopping.\n' \
        "$(c "$BRED" '!!')" "$prog" "$rc" >&2
      exit 1
    fi
    record_updated "$prog" "$method"
  fi
  return 0
}

# --- pre-flight: home hygiene before installs/updates -----------------------

# check_stray_dotfiles -> warn about dotfiles in $HOME (other than XDG-managed
# ones) that a dotfiles checkout could clobber. In a real run this always asks
# to continue; in --echo mode it only lists what it found.
check_stray_dotfiles() {
  local entry name
  local -a stray=()
  for entry in "$HOME"/.[!.]* "$HOME"/..?*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="${entry##*/}"
    case "$name" in
      .config|.local|.cache|.github) continue ;;
    esac
    stray+=("$name")
  done
  [[ ${#stray[@]} -gt 0 ]] || return 0

  printf '\n%s\n' "$(c "$YELLOW" 'warning: stray dotfiles in your home directory:')"
  local s
  for s in "${stray[@]}"; do
    printf '    %s\n' "$(c "$DIM" "$s")"
  done
  printf '  %s\n' "$(c "$DIM" 'a dotfiles checkout may overwrite these')"

  if [[ $RUN -eq 0 ]]; then
    printf '  %s\n' "$(c "$DIM" '(echo mode: not prompting)')"
    return 0
  fi

  local answer
  prompt_read answer "  Continue anyway? [y/N]: "
  case "${answer,,}" in
    y|yes) return 0 ;;
    *)
      printf '  %s\n' "$(c "$YELLOW" 'aborting')"
      exit 1
      ;;
  esac
}

# normalize_xdg_dirs -> rename capitalized XDG user directories to lowercase,
# then refresh them with xdg-user-dirs-update. In --echo mode, only report.
normalize_xdg_dirs() {
  local d lower
  for d in Desktop Downloads Templates Public Documents Music Pictures Videos; do
    lower="${d,,}"
    [[ -d "$HOME/$d" ]] || continue
    if [[ $RUN -eq 0 ]]; then
      printf '  %s would rename %s to %s\n' \
        "$(c "$DIM" '->')" "$(c "$CYAN" "$d")" "$(c "$CYAN" "$lower")"
      continue
    fi
    mv -- "$HOME/$d" "$HOME/${d}_TMP" && mv -- "$HOME/${d}_TMP" "$HOME/$lower"
  done

  if [[ $RUN -eq 0 ]]; then
    printf '  %s would run: xdg-user-dirs-update --force\n' "$(c "$DIM" '->')"
    return 0
  fi
  if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update --force
  else
    printf '  %s\n' "$(c "$DIM" 'xdg-user-dirs-update not found; skipping')"
  fi
}

# cleanup / on_interrupt -> always return to the directory we were launched from.
cleanup() {
  [[ -n "$START_DIR" ]] && cd -- "$START_DIR" 2>/dev/null
  return 0
}

on_interrupt() {
  printf '\n%s\n' "$(c "$YELLOW" 'interrupted')"
  exit 130
}

main() {
  parse_args "$@"
  setup_colors

  if [[ -n "$KIND" ]] && ! validate_kind "$KIND"; then
    printf '%s\n' "$(c "$RED" "error: invalid --kind '${KIND,,}' (allowed: ${ALLOWED_KINDS// /, })")" >&2
    exit 1
  fi

  case "$MODE" in
    list)
      list_programs
      return 0
      ;;
  esac

  if [[ -z "$KIND" ]]; then
    printf '%s\n' "$(c "$RED" "error: --kind is required for '$MODE' mode")" >&2
    printf '%s\n' "$(c "$RED" "       choose one of: ${ALLOWED_KINDS// /, }")" >&2
    exit 1
  fi

  # From here on we run mutating commands; remember where we started so we can
  # return there on any exit or interrupt, and set up the pre-flight.
  START_DIR="$PWD"
  trap cleanup EXIT
  trap on_interrupt INT

  check_stray_dotfiles
  normalize_xdg_dirs

  # distro-tier starts need root; verify sudo up front and abort cleanly if the
  # user neither is root nor can authenticate.
  if [[ $RUN -eq 1 && ${EUID:-$(id -u)} -ne 0 ]]; then
    case "$KIND" in
      UBUNTU|ARCH)
        if ! sudo -v; then
          printf '%s\n' "$(c "$BRED" "error: --kind ${KIND,,} needs sudo, but \"sudo -v\" failed")" >&2
          exit 1
        fi
        ;;
    esac
  fi

  # do the actual installs/updates from /tmp so relative paths and temp files
  # land somewhere disposable.
  if [[ $RUN -eq 1 ]] && ! cd /tmp; then
    printf '%s\n' "$(c "$RED" "error: cannot cd to /tmp")" >&2
    exit 1
  fi

  local prog mgr

  if [[ "$MODE" == "update" ]]; then
    local did=0
    # package manager catch-alls first, run once each
    local -a mgrs=()
    mapfile -t mgrs < <(managers_used)
    if [[ ${#mgrs[@]} -gt 0 ]]; then
      local show_header=1
      for mgr in "${mgrs[@]}"; do
        if [[ $RUN -eq 1 ]] && state_has "$UPDATE_STATE" "$(manager_key "$mgr")"; then
          continue
        fi
        if [[ $show_header -eq 1 ]]; then
          printf '\n%s\n' "$(c "$BOLD" '=== system upgrades ===')"
          show_header=0
        fi
        update_manager "$mgr"
        did=1
        [[ $NEXT -eq 1 ]] && break
      done
    fi
    if [[ $NEXT -eq 0 || $did -eq 0 ]]; then
      # then per-program updates
      for prog in "${PROGRAMS[@]}"; do
        wanted "$prog" || continue
        is_installed "$prog" || continue
        if [[ $RUN -eq 1 ]] && state_has "$UPDATE_STATE" "$prog"; then
          continue
        fi
        if update_one "$prog"; then
          did=1
          [[ $NEXT -eq 1 ]] && break
        fi
      done
    fi
    if [[ $NEXT -eq 1 && $did -eq 0 ]]; then
      printf '\n%s\n' "$(c "$DIM" 'nothing left to update')"
    fi
    if [[ $RUN -eq 1 ]] && ! update_pending && [[ -f "$UPDATE_STATE" ]]; then
      rm -f "$UPDATE_STATE"
      printf '\n%s\n' "$(c "$GREEN" 'all updates complete; cleared update state')"
    fi
    return 0
  fi

  if [[ $NEXT -eq 1 ]]; then
    local target=""
    for prog in "${PROGRAMS[@]}"; do
      wanted "$prog" || continue
      is_installed "$prog" && continue
      if [[ -z "$(methods_for "$prog")" ]]; then
        report_no_method "$prog"
        continue
      fi
      target="$prog"
      break
    done
    if [[ -z "$target" ]]; then
      printf '\n%s\n' "$(c "$DIM" 'nothing left to install')"
      return 0
    fi
    install_one "$target"
    printf '\n%s %s, %s\n' \
      "$(c "$DIM" '--- done:')" \
      "$(c "$GREEN" "$INSTALLED selected")" \
      "$(c "$YELLOW" "$SKIPPED skipped ---")"
    [[ $RUN -eq 1 ]] || printf '%s\n' "$(c "$DIM" '(echo mode: nothing was executed; run without --echo to apply)')"
    return 0
  fi

  local rc=0
  for prog in "${PROGRAMS[@]}"; do
    wanted "$prog" || continue
    if [[ $RUN -eq 1 ]] && is_installed "$prog"; then
      continue
    fi
    install_one "$prog"
    rc=$?
    if [[ $rc -eq 2 ]]; then
      printf '  %s\n' "$(c "$DIM" '-> skipping remaining programs')"
      break
    fi
  done

  printf '\n%s %s, %s\n' \
    "$(c "$DIM" '--- done:')" \
    "$(c "$GREEN" "$INSTALLED selected")" \
    "$(c "$YELLOW" "$SKIPPED skipped ---")"
  [[ $RUN -eq 1 ]] || printf '%s\n' "$(c "$DIM" '(echo mode: nothing was executed; run without --echo to apply)')"
}

main "$@"
