#!/usr/bin/env bash
# Hyprland Session Restore Script v3
# Restores window layout, workspaces, positions, and groups
# Matches multi-window apps (browsers) by title similarity

set -uo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-sessions"
SESSION_FILE="${SESSION_DIR}/default-session.json"

VERBOSE=false
DRY_RUN=false
WORKSPACE_ONLY=false
GROUPS_ONLY=false
LAUNCH_DELAY=2
POLL_INTERVAL=2
POLL_TIMEOUT=30

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file) SESSION_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -w|--workspace-only) WORKSPACE_ONLY=true; shift ;;
        -g|--groups-only) GROUPS_ONLY=true; shift ;;
        --delay) LAUNCH_DELAY="$2"; shift 2 ;;
        --timeout) POLL_TIMEOUT="$2"; shift 2 ;;
        -h|--help)
            cat << EOF
Usage: hypr-restore-session [OPTIONS]

Restore Hyprland session from saved file.

Options:
  -f, --file PATH       Restore from specific file
  -v, --verbose         Show detailed output
  -d, --dry-run         Show what would be done without executing
  -w, --workspace-only  Only move existing windows to saved workspaces
  -g, --groups-only     Only restore window groups
  --delay SECONDS       Delay between launching apps (default: 2)
  --timeout SECONDS     Max wait for windows to appear per app (default: 30)
  -h, --help            Show this help

Restore Modes:
  1. Full restore (default) - Launch apps, restore workspaces, positions, groups
  2. Workspace only (-w)    - Move existing windows to saved workspaces
  3. Groups only (-g)       - Only restore window groups
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
SESSION_VERSION=$(echo "$SESSION_DATA" | jq -r '.version // "1.0"')
SESSION_TIME=$(echo "$SESSION_DATA" | jq -r '.timestamp')
CLIENT_COUNT=$(echo "$SESSION_DATA" | jq '.clients | length')
GROUP_COUNT=$(echo "$SESSION_DATA" | jq '.groups | length // 0')

echo "Session from: $SESSION_TIME ($CLIENT_COUNT windows, $GROUP_COUNT groups)"

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
        kitty|alacritty|wezterm) echo "$class" ;;
        com.mitchellh.ghostty) echo "ghostty" ;;
        firefox|firefox-developer-edition) echo "firefox" ;;
        chromium|chrome|google-chrome) echo "chromium" ;;
        brave-browser) echo "brave --restore-last-session --disable-session-crashed-bubble" ;;
        discord) echo "discord" ;;
        slack) echo "slack" ;;
        spotify) echo "spotify" ;;
        code|vscode) echo "code" ;;
        thunar|nautilus|dolphin) echo "$class" ;;
        steam) echo "steam" ;;
        obsidian) echo "obsidian" ;;
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

# Wait for expected number of windows of a class to appear
wait_for_windows() {
    local class="$1"
    local expected="$2"
    local elapsed=0

    while [ $elapsed -lt "$POLL_TIMEOUT" ]; do
        local current_count
        current_count=$(hyprctl clients -j | jq "[.[] | select(.class == \"$class\")] | length")
        if [ "$current_count" -ge "$expected" ]; then
            $VERBOSE && echo "    Found $current_count/$expected $class windows"
            return 0
        fi
        $VERBOSE && echo "    Waiting for $class windows: $current_count/$expected (${elapsed}s)..."
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    local final_count
    final_count=$(hyprctl clients -j | jq "[.[] | select(.class == \"$class\")] | length")
    echo "  Timeout waiting for $class: got $final_count/$expected windows"
    return 0
}

# Restore window groups
restore_groups() {
    if [ "$GROUP_COUNT" = "0" ] || [ "$GROUP_COUNT" = "null" ]; then
        $VERBOSE && echo "No groups to restore"
        return
    fi

    echo ""
    echo "Restoring window groups..."

    local current_clients=$(hyprctl clients -j)
    local restored_groups=0

    while read -r group; do
        local group_classes=$(echo "$group" | jq -r '.members | map(.class) | join(", ")')
        local group_workspace=$(echo "$group" | jq -r '.workspace.name // .workspace.id')

        $VERBOSE && echo "  Group: $group_classes on $group_workspace"

        local member_classes=$(echo "$group" | jq -r '.members[].class')
        local found_addresses=()

        while read -r member; do
            local member_class=$(echo "$member" | jq -r '.class')

            local addr=$(echo "$current_clients" | jq -r ".[] | select(.class == \"$member_class\" and (.grouped | length == 0)) | .address" | head -1 || true)

            if [ -n "$addr" ] && [ "$addr" != "null" ]; then
                found_addresses+=("$addr")
                current_clients=$(echo "$current_clients" | jq "del(.[] | select(.address == \"$addr\"))")
            fi
        done < <(echo "$group" | jq -c '.members[]')

        if [ ${#found_addresses[@]} -ge 2 ]; then
            if $DRY_RUN; then
                echo "  [DRY] Create group: ${found_addresses[*]}"
            else
                local first="${found_addresses[0]}"
                hyprctl dispatch focuswindow "address:$first" >/dev/null 2>&1 || true
                hyprctl dispatch togglegroup >/dev/null 2>&1 || true

                for addr in "${found_addresses[@]:1}"; do
                    hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
                    hyprctl dispatch moveintogroup l >/dev/null 2>&1 || true
                done

                ((restored_groups++)) || true
                $VERBOSE && echo "    Created group with ${#found_addresses[@]} windows"
            fi
        else
            $VERBOSE && echo "    Could not find enough windows for group"
        fi
    done < <(echo "$SESSION_DATA" | jq -c '.groups[]')

    echo "  Restored $restored_groups groups"
}

# Move windows to saved workspaces using title-based matching for multi-window classes
move_windows_to_workspaces() {
    echo ""
    echo "Moving windows to saved workspaces..."

    local current_clients=$(hyprctl clients -j)
    local moved_count=0

    local multi_window_classes
    multi_window_classes=$(echo "$SESSION_DATA" | jq -r '
        [.clients | group_by(.class)[] | select(length > 1) | .[0].class] | .[]
    ')

    declare -A MULTI_CLASSES
    for cls in $multi_window_classes; do
        MULTI_CLASSES[$cls]=1
    done

    declare -A USED_ADDRESSES

    # First pass: handle multi-window classes with title matching
    for cls in $multi_window_classes; do
        $VERBOSE && echo "  Title-matching $cls windows..."

        local saved_windows
        saved_windows=$(echo "$SESSION_DATA" | jq -c "[.clients[] | select(.class == \"$cls\")]")

        local current_windows
        current_windows=$(echo "$current_clients" | jq -c "[.[] | select(.class == \"$cls\")]")

        local current_count
        current_count=$(echo "$current_windows" | jq 'length')

        if [ "$current_count" -eq 0 ]; then
            $VERBOSE && echo "    No current $cls windows found"
            continue
        fi

        while read -r saved; do
            local saved_title
            saved_title=$(echo "$saved" | jq -r '.title')
            local ws_id
            ws_id=$(echo "$saved" | jq -r '.workspace.id')
            local ws_name
            ws_name=$(echo "$saved" | jq -r '.workspace.name')
            local floating
            floating=$(echo "$saved" | jq -r '.floating')
            local pos_x pos_y size_w size_h
            pos_x=$(echo "$saved" | jq -r '.at[0]')
            pos_y=$(echo "$saved" | jq -r '.at[1]')
            size_w=$(echo "$saved" | jq -r '.size[0]')
            size_h=$(echo "$saved" | jq -r '.size[1]')

            local ws_target
            ws_target=$(get_workspace_target "$ws_id" "$ws_name")

            local best_addr=""
            local best_score=-1

            while read -r candidate; do
                local cand_addr
                cand_addr=$(echo "$candidate" | jq -r '.address')

                if [ -n "${USED_ADDRESSES[$cand_addr]:-}" ]; then
                    continue
                fi

                local cand_title
                cand_title=$(echo "$candidate" | jq -r '.title')

                local score
                score=$(title_similarity "$saved_title" "$cand_title")

                if [ "$score" -gt "$best_score" ]; then
                    best_score=$score
                    best_addr=$cand_addr
                fi
            done < <(echo "$current_windows" | jq -c '.[]')

            if [ -n "$best_addr" ]; then
                USED_ADDRESSES[$best_addr]=1

                if $DRY_RUN; then
                    echo "  [DRY] Move $cls ($saved_title) -> $ws_target (score: $best_score)"
                else
                    $VERBOSE && echo "    $cls -> $ws_target (title score: $best_score)"
                    hyprctl dispatch movetoworkspacesilent "$ws_target,address:$best_addr" >/dev/null 2>&1 || true

                    local is_floating
                    is_floating=$(echo "$current_clients" | jq -r ".[] | select(.address == \"$best_addr\") | .floating")
                    if [ "$floating" = "true" ] && [ "$is_floating" != "true" ]; then
                        hyprctl dispatch togglefloating "address:$best_addr" >/dev/null 2>&1 || true
                    fi
                    if [ "$floating" = "true" ]; then
                        hyprctl dispatch movewindowpixel "exact $pos_x $pos_y,address:$best_addr" >/dev/null 2>&1 || true
                        hyprctl dispatch resizewindowpixel "exact $size_w $size_h,address:$best_addr" >/dev/null 2>&1 || true
                    fi

                    ((moved_count++)) || true
                fi
            else
                $VERBOSE && echo "    No match for $cls: $saved_title"
            fi
        done < <(echo "$saved_windows" | jq -c '.[]')
    done

    # Second pass: handle single-window classes with simple matching
    while read -r client; do
        local class
        class=$(echo "$client" | jq -r '.class')

        if [ -n "${MULTI_CLASSES[$class]:-}" ]; then
            continue
        fi

        local ws_id ws_name floating pos_x pos_y size_w size_h
        ws_id=$(echo "$client" | jq -r '.workspace.id')
        ws_name=$(echo "$client" | jq -r '.workspace.name')
        floating=$(echo "$client" | jq -r '.floating')
        pos_x=$(echo "$client" | jq -r '.at[0]')
        pos_y=$(echo "$client" | jq -r '.at[1]')
        size_w=$(echo "$client" | jq -r '.size[0]')
        size_h=$(echo "$client" | jq -r '.size[1]')

        local ws_target
        ws_target=$(get_workspace_target "$ws_id" "$ws_name")

        local current_address=""
        while read -r cand; do
            local addr
            addr=$(echo "$cand" | jq -r '.address')
            if [ -z "${USED_ADDRESSES[$addr]:-}" ]; then
                current_address="$addr"
                USED_ADDRESSES[$addr]=1
                break
            fi
        done < <(echo "$current_clients" | jq -c ".[] | select(.class == \"$class\")")

        if [ -n "$current_address" ]; then
            if $DRY_RUN; then
                echo "  [DRY] Move $class -> $ws_target"
            else
                $VERBOSE && echo "  Moving $class -> $ws_target"
                hyprctl dispatch movetoworkspacesilent "$ws_target,address:$current_address" >/dev/null 2>&1 || true

                local is_floating
                is_floating=$(echo "$current_clients" | jq -r ".[] | select(.address == \"$current_address\") | .floating")
                if [ "$floating" = "true" ] && [ "$is_floating" != "true" ]; then
                    hyprctl dispatch togglefloating "address:$current_address" >/dev/null 2>&1 || true
                fi
                if [ "$floating" = "true" ]; then
                    hyprctl dispatch movewindowpixel "exact $pos_x $pos_y,address:$current_address" >/dev/null 2>&1 || true
                    hyprctl dispatch resizewindowpixel "exact $size_w $size_h,address:$current_address" >/dev/null 2>&1 || true
                fi

                ((moved_count++)) || true
            fi
        else
            $VERBOSE && echo "  No available window for $class -> $ws_target"
        fi
    done < <(echo "$SESSION_DATA" | jq -c '.clients[]')

    echo "  Moved $moved_count windows"
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
    move_windows_to_workspaces
    restore_groups
    echo ""
    echo "Workspace restoration complete"
    exit 0
fi

# Full restore mode
echo "Full restore: Launching applications..."

# Get expected window counts per class
declare -A EXPECTED_COUNTS
while read -r entry; do
    cls=$(echo "$entry" | jq -r '.key')
    count=$(echo "$entry" | jq -r '.value')
    EXPECTED_COUNTS[$cls]=$count
done < <(echo "$SESSION_DATA" | jq -c '[.clients | group_by(.class)[] | {key: .[0].class, value: length}] | .[]')

declare -A LAUNCHED_CLASSES

while read -r pid_entry; do
    class=$(echo "$pid_entry" | jq -r '.class')

    if [[ -n "${LAUNCHED_CLASSES[$class]:-}" ]]; then
        continue
    fi

    launch_cmd=$(find_launch_command "$class")

    if [ "$launch_cmd" = "SKIP_PWA" ]; then
        $VERBOSE && echo "  Skipping PWA: $class"
        LAUNCHED_CLASSES[$class]=1
        continue
    fi

    expected=${EXPECTED_COUNTS[$class]:-1}

    if $DRY_RUN; then
        echo "  [DRY] Launch: $launch_cmd ($class, expect $expected windows)"
    else
        echo "  Launching: $class (expecting $expected windows)"
        $VERBOSE && echo "    Command: $launch_cmd"
        $launch_cmd >/dev/null 2>&1 &
        sleep "$LAUNCH_DELAY"

        if [ "$expected" -gt 1 ]; then
            wait_for_windows "$class" "$expected"
        fi
    fi
    LAUNCHED_CLASSES[$class]=1
done < <(echo "$SESSION_DATA" | jq -c '.clients | unique_by(.class)[]')

if ! $DRY_RUN; then
    echo ""
    echo "Waiting for windows to settle..."
    sleep 3
fi

move_windows_to_workspaces
restore_groups

echo ""
if $DRY_RUN; then
    echo "Dry run complete (no changes made)"
else
    echo "Session restore complete"
    echo ""
    echo "Tips:"
    echo "  - Browser tabs restore via browser's session restore"
    echo "  - Run 'hrestore -w' after browser tabs load to fix workspaces"
    echo "  - Run 'hrestore -g' to re-create groups if needed"
fi
