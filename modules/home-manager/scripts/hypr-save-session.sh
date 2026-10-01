#!/usr/bin/env bash
# Hyprland Session Save Script v3
# Saves window layout, workspaces, positions, and groups.
# With --auto (the systemd timer) it only writes after this Hyprland
# instance was restored, so a fresh login never overwrites the last save.

set -euo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-sessions"
SESSION_FILE="${SESSION_DIR}/default-session.json"
SNAPSHOT_KEEP=48
MARKER_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-session"

VERBOSE=false
AUTO=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file) SESSION_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --auto) AUTO=true; shift ;;
        -h|--help)
            cat << EOF
Usage: hypr-save-session [OPTIONS]

Save current Hyprland session (windows, workspaces, positions, groups).

Options:
  -f, --file PATH     Save to specific file
  -v, --verbose       Show detailed output
  --auto              Timer mode: save quietly, only after the login restore,
                      and not when the window count drops by more than half
  -h, --help          Show this help

Saved data includes:
  - Window class, title, and workspace (including special/scratch)
  - Window position and size
  - Floating/tiled state
  - Window groups with member order
  - Window order per class (for matching multiple browser windows)

Every save also keeps one snapshot per hour in:
  ~/.local/share/hyprland-sessions/snapshots
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# A systemd timer can hold the signature of a Hyprland that crashed. Use the
# newest live instance in that case.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -S "${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket.sock" ]; then
    newest=$(ls -1t "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null | head -1 || true)
    if [ -z "$newest" ]; then
        $AUTO && exit 0
        echo "Hyprland is not running"
        exit 1
    fi
    export HYPRLAND_INSTANCE_SIGNATURE="$newest"
fi

if $AUTO && [ ! -f "${MARKER_DIR}/restored-${HYPRLAND_INSTANCE_SIGNATURE}" ]; then
    exit 0
fi

SNAPSHOT_DIR="$(dirname "$SESSION_FILE")/snapshots"
mkdir -p "$(dirname "$SESSION_FILE")"
$VERBOSE && echo "Capturing Hyprland session..."

CLIENTS=$(hyprctl clients -j)
WORKSPACES=$(hyprctl workspaces -j)
MONITORS=$(hyprctl monitors -j)

# Hyprland also lists unmapped and zero-size helper surfaces. They cannot be
# restored, so they are left out.
CLIENTS=$(echo "$CLIENTS" | jq '[.[] | select(.mapped != false and .size[0] > 0 and .workspace.id != 0)]')
CLIENT_COUNT=$(echo "$CLIENTS" | jq 'length')

if $AUTO && [ "$CLIENT_COUNT" -eq 0 ]; then
    exit 0
fi

# When many apps close at once, for example after an OOM kill, the timer
# keeps the last good session. A manual save still writes.
if $AUTO && [ -f "$SESSION_FILE" ]; then
    SAVED_COUNT=$(jq '.clients | length' "$SESSION_FILE" 2>/dev/null || echo 0)
    if [ $((CLIENT_COUNT * 2)) -lt "$SAVED_COUNT" ]; then
        echo "Kept the saved session: $CLIENT_COUNT windows now, $SAVED_COUNT saved. Run hsave to save this state."
        exit 0
    fi
fi

SESSION_DATA=$(jq -n \
    --argjson clients "$CLIENTS" \
    --argjson workspaces "$WORKSPACES" \
    --argjson monitors "$MONITORS" \
    '{
        version: "3.0",
        timestamp: now | strflocaltime("%Y-%m-%d %H:%M:%S"),
        activeWorkspace: ($monitors | map(select(.focused))[0].activeWorkspace.name // "1"),
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

# The timer runs every 15 minutes. Skip the write when only the timestamp
# changed.
if $AUTO && [ -f "$SESSION_FILE" ]; then
    old=$(jq -c 'del(.timestamp)' "$SESSION_FILE" 2>/dev/null || true)
    new=$(echo "$SESSION_DATA" | jq -c 'del(.timestamp)')
    [ "$old" = "$new" ] && exit 0
fi

# Write to a temporary file first, so a crash during the write cannot
# leave a half-written session.
echo "$SESSION_DATA" > "${SESSION_FILE}.tmp"
mv -f "${SESSION_FILE}.tmp" "$SESSION_FILE"

mkdir -p "$SNAPSHOT_DIR"
cp -f "$SESSION_FILE" "${SNAPSHOT_DIR}/$(basename "$SESSION_FILE" .json)-$(date +%Y%m%d-%H).json"
ls -1t "$SNAPSHOT_DIR"/*.json 2>/dev/null | tail -n +$((SNAPSHOT_KEEP + 1)) | xargs -r rm -f

$AUTO && exit 0

# A manual save marks this state as good, so the timer can take over.
mkdir -p "$MARKER_DIR"
touch "${MARKER_DIR}/restored-${HYPRLAND_INSTANCE_SIGNATURE}"

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
