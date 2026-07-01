#!/usr/bin/env bash
# Hyprland Session Restore Script v4
# Restores window layout, workspaces, positions, and groups.
# Targets Hyprland's Lua dispatch API (0.55+), where hyprctl dispatch calls
# hl.dispatch(hl.dsp.*). All window moves are issued as a single in-process
# Lua batch, so restore is fast and does not spawn one hyprctl per window.
# Matches multi-window apps (browsers) by title similarity.

set -uo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-sessions"
SESSION_FILE="${SESSION_DIR}/default-session.json"

VERBOSE=false
DRY_RUN=false
WORKSPACE_ONLY=false
GROUPS_ONLY=false
LAUNCH_DELAY=0.4
POLL_INTERVAL=0.3
POLL_TIMEOUT=12
RETURN_WS=1

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file) SESSION_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -w|--workspace-only) WORKSPACE_ONLY=true; shift ;;
        -g|--groups-only) GROUPS_ONLY=true; shift ;;
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
  -w, --workspace-only  Only move existing windows to saved workspaces
  -g, --groups-only     Only restore window groups (best-effort)
  --delay SECONDS       Delay between launching apps (default: 0.4)
  --timeout SECONDS     Max wait for windows to appear (default: 12)
  --return-ws ID        Workspace to focus when done (default: 1)
  -h, --help            Show this help

Restore Modes:
  1. Full restore (default) - Launch missing apps, then place all windows
  2. Workspace only (-w)    - Move existing windows to saved workspaces
  3. Groups only (-g)       - Only restore window groups (best-effort)
  4. Dry run (-d)           - Preview restore actions

Window matching for multi-window apps (browsers):
  Windows are matched by title similarity so each window goes to
  the correct workspace, including scratchpad/special workspaces.
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$SESSION_FILE" ]; then
    echo "Session file not found: $SESSION_FILE"
    exit 1
fi

$VERBOSE && echo "Loading session from: $SESSION_FILE"

SESSION_DATA=$(cat "$SESSION_FILE")
SESSION_TIME=$(echo "$SESSION_DATA" | jq -r '.timestamp')
CLIENT_COUNT=$(echo "$SESSION_DATA" | jq '.clients | length')
GROUP_COUNT=$(echo "$SESSION_DATA" | jq '.groups | length // 0')

echo "Session from: $SESSION_TIME ($CLIENT_COUNT windows, $GROUP_COUNT groups)"

# Collected placement plan (parallel arrays), applied later in one Lua batch.
MOVE_ADDRS=()   # e.g. address:0x1234
MOVE_WS=()      # Lua literal: 5  or  "special:scratchpad"
FLOAT_ADDRS=()  # addresses whose floating state must be toggled

# Get workspace target (handles special workspaces)
get_workspace_target() {
    local workspace_id="$1"
    local workspace_name="$2"

    if [[ "$workspace_id" =~ ^- ]] && [ -n "$workspace_name" ] && [ "$workspace_name" != "null" ]; then
        echo "$workspace_name"
    else
        echo "$workspace_id"
    fi
}

# Render a workspace target as a Lua value: a bare number for normal
# workspaces, a quoted string for named/special ones.
lua_ws_value() {
    local t="$1"
    if [[ "$t" =~ ^-?[0-9]+$ ]]; then
        echo "$t"
    else
        local e=${t//\\/\\\\}
        e=${e//\"/\\\"}
        echo "\"$e\""
    fi
}

# Find launch command for a window class
find_launch_command() {
    local class="$1"

    local config_file="$HOME/.config/hypr/session-commands.conf"
    if [ -f "$config_file" ]; then
        local custom_cmd=$(grep -E "^${class}=" "$config_file" 2>/dev/null | cut -d'=' -f2- || true)
        if [ -n "$custom_cmd" ]; then
            echo "$custom_cmd"
            return
        fi
    fi

    case "${class,,}" in
        kitty|alacritty|wezterm|foot) echo "$class" ;;
        com.mitchellh.ghostty) echo "ghostty" ;;
        firefox|firefox-developer-edition) echo "firefox" ;;
        chromium|chrome|google-chrome) echo "chromium" ;;
        brave-browser) echo "brave --restore-last-session --disable-session-crashed-bubble --ozone-platform=wayland" ;;
        discord) echo "discord" ;;
        slack) echo "slack" ;;
        spotify) echo "spotify" ;;
        code|vscode) echo "code" ;;
        thunar|nautilus|dolphin) echo "$class" ;;
        steam) echo "steam" ;;
        obsidian) echo "obsidian --disable-gpu" ;;
        telegram) echo "telegram-desktop" ;;
        signal) echo "signal-desktop" ;;
        ferdium) echo "ferdium" ;;
        org.keepassxc.keepassxc) echo "keepassxc" ;;
        *)
            if [[ "${class,,}" == brave-*-default ]]; then
                echo "SKIP_PWA"
                return
            fi
            local desktop_file=""
            desktop_file=$(find ~/.local/share/applications /usr/share/applications /run/current-system/sw/share/applications -name "*${class,,}*.desktop" 2>/dev/null | head -1 || true)
            if [ -n "$desktop_file" ]; then
                grep '^Exec=' "$desktop_file" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/%[fFuU]//g' | xargs || echo "${class,,}"
            else
                echo "${class,,}"
            fi
            ;;
    esac
}

# Compute title similarity score (number of matching words)
title_similarity() {
    local saved_title="$1"
    local current_title="$2"

    if [ "$saved_title" = "$current_title" ]; then
        echo 1000
        return
    fi

    local score=0
    local saved_lower="${saved_title,,}"
    local current_lower="${current_title,,}"

    for word in $saved_lower; do
        if [ ${#word} -le 2 ]; then
            continue
        fi
        if [[ "$current_lower" == *"$word"* ]]; then
            ((score++)) || true
        fi
    done

    echo "$score"
}

# Wait until every launched class has at least its expected window count,
# or until the timeout elapses. Polls quickly instead of sleeping blindly.
wait_for_windows() {
    local -n want=$1
    local elapsed_ms=0
    local timeout_ms=$(awk "BEGIN{print int($POLL_TIMEOUT*1000)}")
    local interval_ms=$(awk "BEGIN{print int($POLL_INTERVAL*1000)}")

    while [ "$elapsed_ms" -lt "$timeout_ms" ]; do
        local clients counts satisfied=true
        clients=$(hyprctl clients -j)
        for cls in "${!want[@]}"; do
            local have
            have=$(echo "$clients" | jq --arg c "$cls" '[.[] | select(.class == $c)] | length')
            if [ "$have" -lt "${want[$cls]}" ]; then
                satisfied=false
                $VERBOSE && echo "    waiting: $cls $have/${want[$cls]}"
            fi
        done
        $satisfied && return 0
        sleep "$POLL_INTERVAL"
        elapsed_ms=$((elapsed_ms + interval_ms))
    done
    $VERBOSE && echo "    timeout waiting for windows (continuing anyway)"
    return 0
}

# Apply the collected placement plan in a single Lua batch, then focus the
# return workspace. Window moves under the Lua API follow the window, so we
# always finish by focusing RETURN_WS.
apply_plan() {
    local n=${#MOVE_ADDRS[@]}

    if $DRY_RUN; then
        local i
        for ((i = 0; i < n; i++)); do
            echo "  [DRY] move ${MOVE_ADDRS[$i]} -> ${MOVE_WS[$i]}"
        done
        local a
        for a in "${FLOAT_ADDRS[@]:-}"; do
            [ -n "$a" ] && echo "  [DRY] toggle float $a"
        done
        echo "  [DRY] focus workspace $RETURN_WS"
        return
    fi

    local lua="function()"
    lua+=" local d=hl.dispatch"
    lua+=" local function mv(a,w) pcall(function() d(hl.dsp.window.move({window=a,workspace=w})) end) end"
    lua+=" local function fl(a) pcall(function() d(hl.dsp.window.float({window=a})) end) end"
    local i
    for ((i = 0; i < n; i++)); do
        lua+=" mv(\"${MOVE_ADDRS[$i]}\",${MOVE_WS[$i]})"
    done
    local a
    for a in "${FLOAT_ADDRS[@]:-}"; do
        [ -n "$a" ] && lua+=" fl(\"$a\")"
    done
    lua+=" pcall(function() d(hl.dsp.focus({workspace=$RETURN_WS})) end)"
    lua+=" end"

    hyprctl dispatch "$lua" >/dev/null 2>&1 || true
    echo "  Placed $n windows; focused workspace $RETURN_WS"
}

# Restore window groups (best-effort). Group recreation depends on focus and
# layout, so it is only run on demand (-g) and never blocks the main restore.
restore_groups() {
    if [ "$GROUP_COUNT" = "0" ] || [ "$GROUP_COUNT" = "null" ]; then
        $VERBOSE && echo "No groups to restore"
        return
    fi

    echo ""
    echo "Restoring window groups (best-effort)..."

    local current_clients=$(hyprctl clients -j)
    local restored_groups=0

    while read -r group; do
        local member_classes=$(echo "$group" | jq -r '.members[].class')
        local found_addresses=()

        while read -r member_class; do
            local addr=$(echo "$current_clients" | jq -r --arg c "$member_class" \
                '.[] | select(.class == $c and (.grouped | length == 0)) | .address' | head -1 || true)
            if [ -n "$addr" ] && [ "$addr" != "null" ]; then
                found_addresses+=("$addr")
                current_clients=$(echo "$current_clients" | jq --arg a "$addr" 'del(.[] | select(.address == $a))')
            fi
        done <<< "$member_classes"

        if [ ${#found_addresses[@]} -ge 2 ]; then
            if $DRY_RUN; then
                echo "  [DRY] group: ${found_addresses[*]}"
            else
                local lua="function() local d=hl.dispatch pcall(function()"
                lua+=" d(hl.dsp.focus({window=\"address:${found_addresses[0]}\"}))"
                lua+=" d(hl.dsp.group.toggle())"
                local addr
                for addr in "${found_addresses[@]:1}"; do
                    lua+=" d(hl.dsp.focus({window=\"address:$addr\"}))"
                    lua+=" d(hl.dsp.group.move_window(\"l\"))"
                done
                lua+=" end) end"
                hyprctl dispatch "$lua" >/dev/null 2>&1 || true
                ((restored_groups++)) || true
            fi
        fi
    done < <(echo "$SESSION_DATA" | jq -c '.groups[]')

    echo "  Restored $restored_groups groups"
}

# Build the placement plan: match saved windows to live windows and record
# where each should go. Multi-window classes match by title; single-window
# classes match by class.
build_plan() {
    echo ""
    echo "Matching windows to saved workspaces..."

    local current_clients=$(hyprctl clients -j)

    local multi_window_classes
    multi_window_classes=$(echo "$SESSION_DATA" | jq -r '
        [.clients | group_by(.class)[] | select(length > 1) | .[0].class] | .[]
    ')

    declare -A MULTI_CLASSES
    local cls
    for cls in $multi_window_classes; do
        MULTI_CLASSES[$cls]=1
    done

    declare -A USED_ADDRESSES

    # First pass: multi-window classes, matched by title similarity
    for cls in $multi_window_classes; do
        $VERBOSE && echo "  Title-matching $cls windows..."

        local saved_windows current_windows current_count
        saved_windows=$(echo "$SESSION_DATA" | jq -c --arg c "$cls" '[.clients[] | select(.class == $c)]')
        current_windows=$(echo "$current_clients" | jq -c --arg c "$cls" '[.[] | select(.class == $c)]')
        current_count=$(echo "$current_windows" | jq 'length')

        if [ "$current_count" -eq 0 ]; then
            $VERBOSE && echo "    No current $cls windows found"
            continue
        fi

        while read -r saved; do
            local saved_title ws_id ws_name floating ws_target
            saved_title=$(echo "$saved" | jq -r '.title')
            ws_id=$(echo "$saved" | jq -r '.workspace.id')
            ws_name=$(echo "$saved" | jq -r '.workspace.name')
            floating=$(echo "$saved" | jq -r '.floating')
            ws_target=$(get_workspace_target "$ws_id" "$ws_name")

            local best_addr="" best_score=-1
            while read -r candidate; do
                local cand_addr cand_title score
                cand_addr=$(echo "$candidate" | jq -r '.address')
                [ -n "${USED_ADDRESSES[$cand_addr]:-}" ] && continue
                cand_title=$(echo "$candidate" | jq -r '.title')
                score=$(title_similarity "$saved_title" "$cand_title")
                if [ "$score" -gt "$best_score" ]; then
                    best_score=$score
                    best_addr=$cand_addr
                fi
            done < <(echo "$current_windows" | jq -c '.[]')

            if [ -n "$best_addr" ]; then
                USED_ADDRESSES[$best_addr]=1
                MOVE_ADDRS+=("address:$best_addr")
                MOVE_WS+=("$(lua_ws_value "$ws_target")")
                local is_floating
                is_floating=$(echo "$current_windows" | jq -r --arg a "$best_addr" '.[] | select(.address == $a) | .floating')
                [ "$floating" != "$is_floating" ] && FLOAT_ADDRS+=("address:$best_addr")
                $VERBOSE && echo "    $cls -> $ws_target (title score: $best_score)"
            else
                $VERBOSE && echo "    No match for $cls: $saved_title"
            fi
        done < <(echo "$saved_windows" | jq -c '.[]')
    done

    # Second pass: single-window classes, matched by class
    while read -r client; do
        local class
        class=$(echo "$client" | jq -r '.class')
        [ -n "${MULTI_CLASSES[$class]:-}" ] && continue

        local ws_id ws_name floating ws_target
        ws_id=$(echo "$client" | jq -r '.workspace.id')
        ws_name=$(echo "$client" | jq -r '.workspace.name')
        floating=$(echo "$client" | jq -r '.floating')
        ws_target=$(get_workspace_target "$ws_id" "$ws_name")

        local current_address="" is_floating="false"
        while read -r cand; do
            local addr
            addr=$(echo "$cand" | jq -r '.address')
            if [ -z "${USED_ADDRESSES[$addr]:-}" ]; then
                current_address="$addr"
                is_floating=$(echo "$cand" | jq -r '.floating')
                USED_ADDRESSES[$addr]=1
                break
            fi
        done < <(echo "$current_clients" | jq -c --arg c "$class" '.[] | select(.class == $c)')

        if [ -n "$current_address" ]; then
            MOVE_ADDRS+=("address:$current_address")
            MOVE_WS+=("$(lua_ws_value "$ws_target")")
            [ "$floating" != "$is_floating" ] && FLOAT_ADDRS+=("address:$current_address")
            $VERBOSE && echo "  $class -> $ws_target"
        else
            $VERBOSE && echo "  No available window for $class -> $ws_target"
        fi
    done < <(echo "$SESSION_DATA" | jq -c '.clients[]')

    echo "  Matched ${#MOVE_ADDRS[@]} windows"
}

# Groups only mode
if $GROUPS_ONLY; then
    restore_groups
    echo ""
    echo "Group restoration complete"
    exit 0
fi

# Workspace only mode
if $WORKSPACE_ONLY; then
    build_plan
    apply_plan
    echo ""
    echo "Workspace restoration complete"
    exit 0
fi

# Full restore mode
echo "Full restore: launching missing applications..."

# Expected window counts per class
declare -A EXPECTED_COUNTS
while read -r entry; do
    cls=$(echo "$entry" | jq -r '.key')
    count=$(echo "$entry" | jq -r '.value')
    EXPECTED_COUNTS[$cls]=$count
done < <(echo "$SESSION_DATA" | jq -c '[.clients | group_by(.class)[] | {key: .[0].class, value: length}] | .[]')

# Only launch classes that are not already running, to avoid duplicates.
RUNNING_CLIENTS=$(hyprctl clients -j)
declare -A LAUNCHED_CLASSES
declare -A WAIT_FOR

while read -r class; do
    [ -n "${LAUNCHED_CLASSES[$class]:-}" ] && continue
    LAUNCHED_CLASSES[$class]=1

    local_running=$(echo "$RUNNING_CLIENTS" | jq --arg c "$class" '[.[] | select(.class == $c)] | length')
    if [ "$local_running" -gt 0 ]; then
        $VERBOSE && echo "  Already running: $class ($local_running)"
        continue
    fi

    launch_cmd=$(find_launch_command "$class")
    if [ "$launch_cmd" = "SKIP_PWA" ]; then
        $VERBOSE && echo "  Skipping PWA: $class"
        continue
    fi

    if $DRY_RUN; then
        echo "  [DRY] launch: $launch_cmd ($class)"
    else
        echo "  Launching: $class"
        $VERBOSE && echo "    Command: $launch_cmd"
        $launch_cmd >/dev/null 2>&1 &
        WAIT_FOR[$class]=${EXPECTED_COUNTS[$class]:-1}
        sleep "$LAUNCH_DELAY"
    fi
done < <(echo "$SESSION_DATA" | jq -r '.clients | unique_by(.class)[] | .class')

if ! $DRY_RUN && [ ${#WAIT_FOR[@]} -gt 0 ]; then
    echo ""
    echo "Waiting for launched windows..."
    wait_for_windows WAIT_FOR
fi

build_plan
apply_plan

echo ""
if $DRY_RUN; then
    echo "Dry run complete (no changes made)"
else
    echo "Session restore complete"
    echo ""
    echo "Tips:"
    echo "  - Browser tabs restore via the browser's own session restore"
    echo "    (Brave: Settings > On startup > Continue where you left off)"
    echo "  - Run 'hrestore -w' after tabs load to re-fix workspaces"
    echo "  - Run 'hrestore -g' to re-create window groups"
fi
