#!/usr/bin/env bash
# Hyprland Session Restore Script v5
# Restores window layout, workspaces, positions, and groups.
# Targets Hyprland's Lua dispatch API (0.55+), where hyprctl dispatch calls
# hl.dispatch(hl.dsp.*). All window moves are issued as a single in-process
# Lua batch, so restore is fast and does not spawn one hyprctl per window.
# Matches multi-window apps (browsers) by title similarity.
# With --auto it runs from Hyprland's autostart after every login.

set -uo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-sessions"
SESSION_FILE="${SESSION_DIR}/default-session.json"
MARKER_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-session"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-session/restore.log"
STAGE_WS="special:hyprrestore"
GROUP_WS="name:hyprgroup"

VERBOSE=false
DRY_RUN=false
WORKSPACE_ONLY=false
AUTO=false
LAUNCH_DELAY=0.4
POLL_INTERVAL=0.5
POLL_TIMEOUT=15
SETTLE=5
RETURN_WS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file) SESSION_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -w|--workspace-only) WORKSPACE_ONLY=true; shift ;;
        -g|--groups-only) WORKSPACE_ONLY=true; shift ;;
        --auto) AUTO=true; VERBOSE=true; POLL_TIMEOUT=45; shift ;;
        --delay) LAUNCH_DELAY="$2"; shift 2 ;;
        --timeout) POLL_TIMEOUT="$2"; shift 2 ;;
        --return-ws) RETURN_WS="$2"; shift 2 ;;
        -h|--help)
            cat << EOF
Usage: hypr-restore-session [OPTIONS]

Restore Hyprland session from saved file.

Options:
  -f, --file PATH       Restore from specific file
  -v, --verbose         Show detailed output
  -d, --dry-run         Show what would be done without executing
  -w, --workspace-only  Only move existing windows to saved places and groups
  -g, --groups-only     Same as -w (groups are part of every placement)
  --auto                Login mode: wait for Hyprland, log to
                        $LOG_FILE
  --delay SECONDS       Delay between launching apps (default: 0.4)
  --timeout SECONDS     Max wait for windows to appear (default: 15)
  --return-ws ID        Workspace to focus when done (default: the saved one)
  -h, --help            Show this help

Restore Modes:
  1. Full restore (default) - Launch missing apps, then place all windows
  2. Workspace only (-w)    - Move existing windows to saved places
  3. Dry run (-d)           - Preview restore actions

Placement:
  - Each window goes to its saved workspace, also special ones such as
    the scratchpad console.
  - Tiled windows go back in their saved left-to-right order.
  - Floating windows get their saved position and size.
  - Window groups are built again with their saved members and order.
  - Browser windows are matched by title similarity.

After a restore, the systemd timer saves the session every 15 minutes.
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if $AUTO; then
    mkdir -p "$(dirname "$LOG_FILE")"
    exec >> "$LOG_FILE" 2>&1
    echo ""
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') auto restore"
fi

# Autosave starts once this Hyprland instance has a marker. The login
# restore always sets it, also when the restore fails, so a failed restore
# cannot stop the saves for the whole session.
mark_restored() {
    $DRY_RUN && return
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return
    mkdir -p "$MARKER_DIR"
    touch "${MARKER_DIR}/restored-${HYPRLAND_INSTANCE_SIGNATURE}"
}
$AUTO && trap mark_restored EXIT

if $AUTO; then
    # Autostart can run before the IPC socket answers.
    for _ in $(seq 1 60); do
        hyprctl monitors -j >/dev/null 2>&1 && break
        sleep 0.5
    done
    # Give the shell and the portals a moment before the apps start.
    sleep 2
fi

if [ ! -f "$SESSION_FILE" ]; then
    echo "Session file not found: $SESSION_FILE"
    exit 1
fi

$VERBOSE && echo "Loading session from: $SESSION_FILE"

SESSION_DATA=$(cat "$SESSION_FILE")
SESSION_TIME=$(echo "$SESSION_DATA" | jq -r '.timestamp')
CLIENT_COUNT=$(echo "$SESSION_DATA" | jq '.clients | length')
GROUP_COUNT=$(echo "$SESSION_DATA" | jq '.groups | length // 0')
[ -z "$RETURN_WS" ] && RETURN_WS=$(echo "$SESSION_DATA" | jq -r '.activeWorkspace // "1"')

echo "Session from: $SESSION_TIME ($CLIENT_COUNT windows, $GROUP_COUNT groups)"

# Live windows that can be placed. Hyprland also lists unmapped helper
# surfaces, which are left out.
live_clients() {
    hyprctl clients -j | jq '[.[] | select(.mapped != false and .size[0] > 0 and .workspace.id != 0)]'
}

# Launch command for a desktop file whose StartupWMClass or file name
# matches the window class.
desktop_command() {
    local class="${1,,}"
    local dirs=(
        "$HOME/.local/share/applications"
        "/etc/profiles/per-user/$USER/share/applications"
        "$HOME/.nix-profile/share/applications"
        "/run/current-system/sw/share/applications"
    )
    local file="" d f
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.desktop; do
            [ -f "$f" ] || continue
            if grep -qix "StartupWMClass=${class}" "$f" 2>/dev/null; then
                file="$f"
                break 2
            fi
        done
    done
    if [ -z "$file" ]; then
        for d in "${dirs[@]}"; do
            [ -f "$d/${class}.desktop" ] && { file="$d/${class}.desktop"; break; }
        done
    fi
    [ -n "$file" ] || return 1
    grep -m1 '^Exec=' "$file" | cut -d'=' -f2- | sed -E 's/ ?%[fFuUick]//g'
}

# Find launch command for a window class. Prints nothing when the class
# has no known command.
find_launch_command() {
    local class="$1"

    local config_file="$HOME/.config/hypr/session-commands.conf"
    if [ -f "$config_file" ]; then
        local custom_cmd
        custom_cmd=$(grep -E "^${class}=" "$config_file" 2>/dev/null | cut -d'=' -f2- || true)
        if [ -n "$custom_cmd" ]; then
            echo "$custom_cmd"
            return
        fi
    fi

    case "${class,,}" in
        kitty|alacritty|wezterm|foot) echo "${class,,}" ;;
        com.mitchellh.ghostty) echo "ghostty" ;;
        firefox|firefox-developer-edition) echo "firefox" ;;
        chromium|chrome|google-chrome) echo "chromium --restore-last-session" ;;
        # Brave restores all its windows and tabs from its own session.
        # The crash bubble would otherwise ask first.
        brave-browser) echo "brave --restore-last-session --disable-session-crashed-bubble" ;;
        obsidian|md.obsidian.obsidian) echo "obsidian" ;;
        telegram|org.telegram.desktop) echo "telegram-desktop" ;;
        signal) echo "signal-desktop" ;;
        org.keepassxc.keepassxc) echo "keepassxc" ;;
        *)
            desktop_command "$class" && return
            command -v "${class,,}" 2>/dev/null || true
            ;;
    esac
}

# Apps that open one window per launch and do not restore their own
# windows. They are launched once per saved window.
one_window_per_launch() {
    case "${1,,}" in
        kitty|alacritty|wezterm|foot|com.mitchellh.ghostty) return 0 ;;
        *) return 1 ;;
    esac
}

# Brave and Chrome web apps have classes like brave-<app id>-Default. The
# browser can reopen them itself, so they are launched only after the
# browser has settled and only when they are still missing.
is_web_app() {
    [[ "${1,,}" =~ ^(brave|chrome|chromium)-.+-(default|profile_[0-9]+)$ ]]
}

# Start an app through Hyprland. Its windows open on the hidden staging
# workspace, so they do not take the focus before they are placed.
launch() {
    local class="$1" cmd="$2"
    if $DRY_RUN; then
        echo "  [DRY] launch: $cmd ($class)"
        return
    fi
    echo "  Launching: $class"
    $VERBOSE && echo "    Command: $cmd"
    local rule
    rule=$(jq -n --arg c "[workspace $STAGE_WS silent] sh -c $(printf '%q' "$cmd")" '$c')
    hyprctl dispatch "function() hl.dispatch(hl.dsp.exec_cmd($rule)) end" >/dev/null 2>&1
    sleep "$LAUNCH_DELAY"
}

# Windows that are still on the staging workspace after the placement had
# no saved place. Move them to the return workspace.
sweep_stage() {
    $DRY_RUN && return
    local lua ws
    ws=$(jq -n --arg w "$RETURN_WS" '$w')
    lua=$(live_clients | jq -r --arg s "$STAGE_WS" --argjson ws "$ws" '
        [.[] | select(.workspace.name == $s)
         | " pcall(function() hl.dispatch(hl.dsp.window.move({window=\("address:" + .address | tojson),workspace=\($ws | tojson),follow=false})) end)"]
        | if length > 0 then "function()" + add + " end" else "" end')
    [ -n "$lua" ] || return
    echo "  Moving windows without a saved place to workspace $RETURN_WS"
    hyprctl dispatch "$lua" >/dev/null 2>&1 || true
}

# Wait until every launched class has at least its expected window count,
# or until the timeout elapses.
wait_for_windows() {
    local -n want=$1
    [ ${#want[@]} -gt 0 ] || return 0
    local elapsed_ms=0
    local timeout_ms=$(awk "BEGIN{print int($POLL_TIMEOUT*1000)}")
    local interval_ms=$(awk "BEGIN{print int($POLL_INTERVAL*1000)}")

    echo ""
    echo "Waiting for launched windows..."
    while [ "$elapsed_ms" -lt "$timeout_ms" ]; do
        local counts satisfied=true cls have
        counts=$(live_clients | jq -c 'group_by(.class) | map({key: .[0].class, value: length}) | from_entries')
        for cls in "${!want[@]}"; do
            have=$(echo "$counts" | jq --arg c "$cls" '.[$c] // 0')
            if [ "$have" -lt "${want[$cls]}" ]; then
                satisfied=false
            fi
        done
        $satisfied && return 0
        sleep "$POLL_INTERVAL"
        elapsed_ms=$((elapsed_ms + interval_ms))
    done
    for cls in "${!want[@]}"; do
        have=$(live_clients | jq --arg c "$cls" '[.[] | select(.class == $c)] | length')
        [ "$have" -lt "${want[$cls]}" ] && echo "  Timeout: $cls has $have of ${want[$cls]} windows"
    done
    return 0
}

# Match saved windows to live windows and write the placement as one Lua
# function. The match is greedy on title similarity within each class; a
# tie goes to the window with the same rank in its class.
#
# The Lua function:
#   1. dissolves the live groups of the matched windows, because a move
#      of one group member moves the whole group,
#   2. moves every matched window to a hidden staging workspace,
#   3. sets each window's floating state there,
#   4. builds each saved group on an empty helper workspace: the first
#      member becomes a group, and each next member joins it from the side
#      where it is tiled. On a workspace with more windows that side can
#      hold another window. The finished group goes back to staging,
#   5. moves the tiled windows and groups to their workspaces in saved
#      left-to-right, top-to-bottom order, so the layout rebuilds in that
#      order,
#   6. moves the floating windows and sets their position and size,
#   7. focuses the return target.
PLAN_JQ='
def words: ascii_downcase | [scan("[a-z0-9]{3,}")] | unique;
def score($a; $b):
    if $a == $b then 1000
    else ($a | words) as $wa | ($b | words) as $wb | ($wa - ($wa - $wb)) | length
    end;
def ranked: group_by(.class) | map(to_entries | map(.value + {rank: .key})) | add // [];
def target:
    if .workspace.id < 0 then .workspace.name
    elif (.workspace.name | test("^[0-9]+$")) then .workspace.name
    else "name:" + .workspace.name
    end;
def lua: tojson;

($saved.clients | to_entries | map(.value + {sidx: .key}) | ranked) as $S
| ($cur | to_entries | map(.value + {cidx: .key}) | ranked) as $C
| [ $S[] as $s | $C[] | select(.class == $s.class)
    | {s: $s.sidx, c: .cidx, score: score($s.title; .title), dist: ((.rank - $s.rank) | fabs)} ]
| sort_by(-.score, .dist, .s)
| reduce .[] as $p ({us: {}, uc: {}, pairs: []};
    if .us[$p.s | tostring] or .uc[$p.c | tostring] then .
    else .us[$p.s | tostring] = true | .uc[$p.c | tostring] = true | .pairs += [$p]
    end)
| [ .pairs[] as $p
    | ($S[] | select(.sidx == $p.s)) as $s
    | ($C[] | select(.cidx == $p.c)) as $c
    | {addr: ("address:" + $c.address), saved: $s.address, class: $s.class, title: $s.title,
       ws: ($s | target), float: $s.floating, toggle: ($s.floating != $c.floating),
       at: $s.at, size: $s.size, score: $p.score} ]
| sort_by(.ws, .at[0], .at[1])
| . as $plan
| ($plan | map({key: .saved, value: .addr}) | from_entries) as $live
| ($plan | map(.addr)) as $placed
| ([ $cur[] | select(.grouped | length > 0) | .grouped | sort ] | unique
    | map(map("address:" + .)) | map(select(any(.[]; . as $a | $placed | index($a))))) as $dissolve
| ([ ($saved.groups // [])[] | select(.workspace.id > 0)
    | [ .members[].address | $live[.] // empty ] | select(length > 1) ]) as $groups
| ([ $groups[] | .[1:][] ]) as $followers
| {
    plan: $plan,
    groups: ($groups | length),
    lua: ( "function() local d=hl.dispatch"
        + " local function mv(a,w) pcall(function() d(hl.dsp.window.move({window=a,workspace=w,follow=false})) end) end"
        + " local function tf(a) pcall(function() d(hl.dsp.window.float({window=a,action=\"toggle\"})) end) end"
        + " local function pl(a,x,y,w,h) pcall(function() d(hl.dsp.window.resize({window=a,x=w,y=h})) d(hl.dsp.window.move({window=a,x=x,y=y})) end) end"
        + " local function gt(a) pcall(function() d(hl.dsp.focus({window=a})) d(hl.dsp.group.toggle()) end) end"
        + " local function gj(l,m) pcall(function()"
        +   " local L=hl.get_window(l) local M=hl.get_window(m) if not L or not M then return end"
        +   " local dx=M.at.x-L.at.x local dy=M.at.y-L.at.y local dir"
        +   " if math.abs(dx)>=math.abs(dy) then dir=(dx>0) and \"l\" or \"r\" else dir=(dy>0) and \"u\" or \"d\" end"
        +   " d(hl.dsp.focus({window=m})) d(hl.dsp.window.move({into_group=dir})) end) end"
        + ([ $dissolve[] | " gt(\(.[0] | lua))" ] | add // "")
        + ([ $plan[] | " mv(\(.addr | lua),\($stage | lua))" ] | add // "")
        + ([ $plan[] | select(.toggle) | " tf(\(.addr | lua))" ] | add // "")
        + ([ $groups[] | .[0] as $l
            | " mv(\($l | lua),\($grp | lua)) gt(\($l | lua))"
            + ([ .[1:][] | " mv(\(. | lua),\($grp | lua)) gj(\($l | lua),\(. | lua))" ] | add)
            + " pcall(function() d(hl.dsp.focus({window=\($l | lua)})) end) mv(\($l | lua),\($stage | lua))" ] | add // "")
        + ([ $plan[] | select(.float | not) | select(.addr as $a | $followers | index($a) | not) | " mv(\(.addr | lua),\(.ws | lua))" ] | add // "")
        + ([ $plan[] | select(.float) | " mv(\(.addr | lua),\(.ws | lua)) pl(\(.addr | lua),\(.at[0]),\(.at[1]),\(.size[0]),\(.size[1]))" ] | add // "")
        + $focus
        + " end" )
  }
'

# Place all live windows by the saved session.
place_windows() {
    local focus_lua="$1"
    local current plan n g
    current=$(live_clients)
    plan=$(jq -n --argjson saved "$SESSION_DATA" --argjson cur "$current" \
        --arg stage "$STAGE_WS" --arg grp "$GROUP_WS" --arg focus "$focus_lua" "$PLAN_JQ")
    n=$(echo "$plan" | jq '.plan | length')
    g=$(echo "$plan" | jq '.groups')

    echo ""
    echo "Placing windows..."
    if $VERBOSE || $DRY_RUN; then
        echo "$plan" | jq -r '.plan[] | "  \(.ws)\t\(if .float then "float \(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else "tiled" end)\t\(.class) (score \(.score)): \(.title[0:40])"'
    fi
    if $DRY_RUN; then
        echo "  [DRY] $n windows, $g groups, focus $RETURN_WS"
        return
    fi
    hyprctl dispatch "$(echo "$plan" | jq -r '.lua')" >/dev/null 2>&1 || true
    echo "  Placed $n of $CLIENT_COUNT saved windows, $g groups"
}

# Lua that focuses a workspace when the placement is done.
focus_workspace_lua() {
    local ws
    ws=$(jq -n --arg w "$1" '$w')
    echo " pcall(function() d(hl.dsp.focus({workspace=$ws})) end)"
}

# Lua that focuses the window that had the focus before the placement.
focus_window_lua() {
    local addr
    addr=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
    [ -n "$addr" ] || return
    echo " pcall(function() d(hl.dsp.focus({window=\"address:$addr\"})) end)"
}

# Workspace only mode
if $WORKSPACE_ONLY; then
    place_windows "$(focus_window_lua)"
    mark_restored
    echo ""
    echo "Workspace restoration complete"
    exit 0
fi

# Full restore mode
echo "Full restore: launching missing applications..."

declare -A EXPECTED_COUNTS
while read -r entry; do
    cls=$(echo "$entry" | jq -r '.key')
    EXPECTED_COUNTS[$cls]=$(echo "$entry" | jq -r '.value')
done < <(echo "$SESSION_DATA" | jq -c '.clients | group_by(.class)[] | {key: .[0].class, value: length}')

RUNNING_COUNTS=$(live_clients | jq -c 'group_by(.class) | map({key: .[0].class, value: length}) | from_entries')

# Launch every class that has fewer windows than saved. Web apps wait for
# the second pass.
declare -A WAIT_FOR
WEB_APPS=()
for class in "${!EXPECTED_COUNTS[@]}"; do
    running=$(echo "$RUNNING_COUNTS" | jq --arg c "$class" '.[$c] // 0')
    want=${EXPECTED_COUNTS[$class]}
    if is_web_app "$class"; then
        [ "$running" -eq 0 ] && WEB_APPS+=("$class")
        continue
    fi
    if one_window_per_launch "$class"; then
        missing=$((want - running))
    else
        missing=$(( running > 0 ? 0 : 1 ))
    fi
    if [ "$missing" -le 0 ]; then
        $VERBOSE && echo "  Already running: $class ($running)"
        continue
    fi

    launch_cmd=$(find_launch_command "$class")
    if [ -z "$launch_cmd" ]; then
        echo "  No launch command for: $class (add one to ~/.config/hypr/session-commands.conf)"
        continue
    fi
    for _ in $(seq 1 "$missing"); do
        launch "$class" "$launch_cmd"
    done
    WAIT_FOR[$class]=$want
done

$DRY_RUN || wait_for_windows WAIT_FOR

# Second pass: web apps that the browser did not reopen by itself.
declare -A WAIT_WEB
if [ ${#WEB_APPS[@]} -gt 0 ]; then
    running_now=$(live_clients)
    for class in "${WEB_APPS[@]}"; do
        n=$(echo "$running_now" | jq --arg c "$class" '[.[] | select(.class == $c)] | length')
        [ "$n" -gt 0 ] && continue
        launch_cmd=$(desktop_command "$class" || true)
        if [ -z "$launch_cmd" ]; then
            echo "  No desktop file for web app: $class"
            continue
        fi
        launch "$class" "$launch_cmd"
        WAIT_WEB[$class]=${EXPECTED_COUNTS[$class]}
    done
    $DRY_RUN || wait_for_windows WAIT_WEB
fi

place_windows "$(focus_workspace_lua "$RETURN_WS")"

# Browser windows show their final titles only after the tabs load, and
# late windows can still appear. A second pass fixes those.
if ! $DRY_RUN && [ ${#WAIT_FOR[@]} -gt 0 ]; then
    sleep "$SETTLE"
    place_windows "$(focus_workspace_lua "$RETURN_WS")"
fi
sweep_stage

mark_restored

echo ""
if $DRY_RUN; then
    echo "Dry run complete (no changes made)"
else
    echo "Session restore complete"
    $AUTO || {
        echo ""
        echo "Tip: run 'hrestore -w' to put the windows back in their saved places"
    }
fi
