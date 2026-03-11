#!/usr/bin/env bash
# Hyprland Session Save Script v2
# Saves window layout, workspaces, positions, and groups

set -euo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-sessions"
SESSION_FILE="${SESSION_DIR}/default-session.json"

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file) SESSION_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help)
            cat << EOF
Usage: hypr-save-session [OPTIONS]

Save current Hyprland session (windows, workspaces, positions, groups).

Options:
  -f, --file PATH     Save to specific file
  -v, --verbose       Show detailed output
  -h, --help          Show this help

Saved data includes:
  - Window class, title, and workspace (including special/scratch)
  - Window position and size
  - Floating/tiled state
  - Window groups with member order
  - Window order per class (for matching multiple browser windows)
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$SESSION_DIR"
$VERBOSE && echo "Capturing Hyprland session..."

CLIENTS=$(hyprctl clients -j)
WORKSPACES=$(hyprctl workspaces -j)
MONITORS=$(hyprctl monitors -j)

SESSION_DATA=$(jq -n \
    --argjson clients "$CLIENTS" \
    --argjson workspaces "$WORKSPACES" \
    --argjson monitors "$MONITORS" \
    '{
        version: "2.0",
        timestamp: now | strftime("%Y-%m-%d %H:%M:%S"),
        clients: [
            $clients | to_entries | sort_by(.value.workspace.id, .value.at[0], .value.at[1])[] | {
                index: .key,
                address: .value.address,
                class: .value.class,
                initialClass: .value.initialClass,
                title: .value.title,
                initialTitle: .value.initialTitle,
                workspace: .value.workspace,
                monitor: .value.monitor,
                at: .value.at,
                size: .value.size,
                floating: .value.floating,
                fullscreen: .value.fullscreen,
                pseudo: .value.pseudo,
                pinned: .value.pinned,
                hidden: .value.hidden,
                pid: .value.pid,
                xwayland: .value.xwayland,
                grouped: .value.grouped
            }
        ],
        groups: [
            ($clients | map(select(.grouped | length > 0))) as $grouped |
            ($grouped | map(.grouped | sort | join(",")) | unique) as $groupKeys |
            $groupKeys[] | . as $key |
            ($grouped | map(select((.grouped | sort | join(",")) == $key))) as $members |
            {
                id: $key,
                workspace: $members[0].workspace,
                members: [
                    $members[0].grouped[] as $addr |
                    ($members | map(select(.address == $addr))[0] // null) |
                    if . then {address: .address, class: .class, title: .title} else null end
                ] | map(select(. != null))
            }
        ],
        classOrder: (
            [$clients | group_by(.class)[] | {
                key: .[0].class,
                value: [.[] | {
                    address: .address,
                    workspace: .workspace,
                    title: .title,
                    initialTitle: .initialTitle,
                    at: .at
                }]
            }] | from_entries
        ),
        workspaces: $workspaces | map({
            id: .id,
            name: .name,
            monitor: .monitor,
            windows: .windows
        }),
        monitors: $monitors | map({
            id: .id,
            name: .name,
            width: .width,
            height: .height,
            activeWorkspace: .activeWorkspace.id
        })
    }')

echo "$SESSION_DATA" > "$SESSION_FILE"

CLIENT_COUNT=$(echo "$CLIENTS" | jq 'length')
WORKSPACE_COUNT=$(echo "$WORKSPACES" | jq 'length')
GROUP_COUNT=$(echo "$SESSION_DATA" | jq '.groups | length')
SPECIAL_COUNT=$(echo "$CLIENTS" | jq '[.[] | select(.workspace.id < 0)] | length')

if $VERBOSE; then
    echo "Session saved to: $SESSION_FILE"
    echo "  - Windows: $CLIENT_COUNT (including $SPECIAL_COUNT in special workspaces)"
    echo "  - Workspaces: $WORKSPACE_COUNT"
    echo "  - Window groups: $GROUP_COUNT"
    echo ""
    echo "Window summary:"
    echo "$CLIENTS" | jq -r '.[] | "  [\(.workspace.name // .workspace.id)] \(.class): \(.title | .[0:50])"' | head -25
    if [ "$CLIENT_COUNT" -gt 25 ]; then
        echo "  ... and $(($CLIENT_COUNT - 25)) more"
    fi
    if [ "$GROUP_COUNT" -gt 0 ]; then
        echo ""
        echo "Groups:"
        echo "$SESSION_DATA" | jq -r '.groups[] | "  [\(.workspace.name // .workspace.id)] \(.members | map(.class) | join(" + "))"'
    fi
else
    echo "Saved $CLIENT_COUNT windows ($GROUP_COUNT groups) across $WORKSPACE_COUNT workspaces"
    echo "  -> $SESSION_FILE"
fi
