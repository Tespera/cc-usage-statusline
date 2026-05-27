#!/usr/bin/env bash
# Claude Code usage statusline.
#
# Left  : model name + context-window % (mirrors cc's default statusline)
# Right : 5-hour and 7-day rate-limit utilization, with reset countdowns,
#         right-aligned and color-coded (green <50%, yellow 50-79%, red >=80%).
#
# Everything is read from the JSON Claude Code passes on stdin — no network
# calls, no credentials, no cache. Works on macOS and Linux.

set -uo pipefail

# ---- tunables ----
WARN=50           # >= this % -> yellow
CRIT=80           # >= this % -> red
RIGHT_MARGIN=6    # columns kept free on the right for cc's own notifications

# ---- ANSI ----
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
# U+2060 WORD JOINER: zero-width and non-whitespace. cc strips leading whitespace from
# statusline output, so this anchor keeps our right-alignment padding from being trimmed.
WJ=$'\xe2\x81\xa0'
EMDASH=$'\xe2\x80\x94'

color_for() {
  local p=$1
  if   (( p < WARN )); then printf '%s' "$GREEN"
  elif (( p < CRIT )); then printf '%s' "$YELLOW"
  else printf '%s' "$RED"
  fi
}

# unix epoch -> "4h26m" / "23m" / "12h"
time_until() {
  local ts=$1 now diff h m
  if [[ -z "$ts" || "$ts" == "null" || "$ts" == "0" ]]; then printf '%s' "$EMDASH"; return; fi
  now=$(date +%s); diff=$(( ts - now ))
  if (( diff <= 0 )); then printf '0m'; return; fi
  h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   (( h == 0 )); then printf '%dm' "$m"
  elif (( m == 0 )); then printf '%dh' "$h"
  else printf '%dh%dm' "$h" "$m"
  fi
}

# ---- read stdin JSON ----
STDIN_JSON=""
[[ ! -t 0 ]] && STDIN_JSON=$(cat 2>/dev/null || true)
jqv() { printf '%s' "$STDIN_JSON" | jq -r "$1 // empty" 2>/dev/null; }

# ---- terminal width ----
# cc runs this command without a controlling tty, so resolve cc's (parent's) tty
# and ask it for the width. Falls back to $COLUMNS, then 80.
get_cols() {
  local tty_name dev cols
  tty_name=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
  if [[ -n "$tty_name" && "$tty_name" != "?" && "$tty_name" != "??" ]]; then
    dev="/dev/$tty_name"                       # Linux: pts/0 -> /dev/pts/0
    [[ ! -e "$dev" ]] && dev="/dev/tty$tty_name" # macOS: s001 -> /dev/ttys001
    if [[ -e "$dev" ]]; then
      cols=$(stty size <"$dev" 2>/dev/null | awk '{print $2}')
      [[ -n "$cols" && "$cols" != "0" ]] && { echo "$cols"; return; }
    fi
  fi
  echo "${COLUMNS:-80}"
}
COLS=$(get_cols)

# ---- left segment: model + context% ----
left_plain=""; left=""
model_name=$(jqv '.model.display_name')
ctx_pct=$(jqv '.context_window.used_percentage')
if [[ -n "$model_name" ]]; then
  left_plain="[$model_name]"
  left="$DIM[$model_name]$RESET"
  if [[ -n "$ctx_pct" ]]; then
    left_plain="$left_plain ${ctx_pct}% context"
    left="$left ${ctx_pct}% context"
  fi
fi

# ---- right segment: 5h / 7d rate limits ----
h5_pct=$(jqv '.rate_limits.five_hour.used_percentage')
d7_pct=$(jqv '.rate_limits.seven_day.used_percentage')
h5_reset=$(time_until "$(jqv '.rate_limits.five_hour.resets_at')")
d7_reset=$(time_until "$(jqv '.rate_limits.seven_day.resets_at')")

if [[ -n "$h5_pct" && -n "$d7_pct" ]]; then
  right_plain="5h ${h5_pct}% ${h5_reset} | 7d ${d7_pct}% ${d7_reset}"
  c5=$(color_for "$h5_pct"); c7=$(color_for "$d7_pct")
  right="5h ${c5}${h5_pct}%${RESET} ${DIM}${h5_reset}${RESET} | 7d ${c7}${d7_pct}%${RESET} ${DIM}${d7_reset}${RESET}"
else
  right_plain="5h ${EMDASH} | 7d ${EMDASH}"
  right="${DIM}5h ${EMDASH}${RESET} | ${DIM}7d ${EMDASH}${RESET}"
fi

# ---- layout: WJ + left + <pad spaces> + right ----
# If the combined line would overflow, drop the right (our addon) and keep the
# left (cc's official model/context). If there is no left either, show right only.
pad=$(( COLS - ${#left_plain} - ${#right_plain} - RIGHT_MARGIN ))
if (( pad < 1 )); then
  if [[ -n "$left_plain" ]]; then
    printf '%s%s' "$WJ" "$left"
    exit 0
  fi
  pad=$(( COLS - ${#right_plain} - RIGHT_MARGIN ))
  (( pad < 0 )) && pad=0
fi

printf '%s%s%*s%s' "$WJ" "$left" "$pad" "" "$right"
