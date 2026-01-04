#!/usr/bin/env bash
# Save Hyprland session state

SESSION_FILE="${HOME}/.config/hypr/session.json"
RESTORE_SCRIPT="${HOME}/.config/hypr/session-restore.sh"

echo "Saving Hyprland session to ${SESSION_FILE}..."

# Get all clients with their details
hyprctl clients -j > "${SESSION_FILE}"

# Generate restore script
cat > "${RESTORE_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
# Auto-generated Hyprland session restore script

SESSION_FILE="${HOME}/.config/hypr/session.json"

if [ ! -f "${SESSION_FILE}" ]; then
    echo "No session file found at ${SESSION_FILE}"
    exit 1
fi

echo "Restoring Hyprland session..."

# Parse session and restore windows
jq -r '.[] | "\(.class)|\(.workspace.id)|\(.title)"' "${SESSION_FILE}" | while IFS='|' read -r class workspace title; do
    echo "Restoring: ${class} on workspace ${workspace}"

    # Launch application on specific workspace
    # Note: This is simplified - you may need to customize launch commands
    case "${class}" in
        firefox|Firefox)
            hyprctl dispatch workspace ${workspace}
            firefox &
            ;;
        obsidian|Obsidian)
            hyprctl dispatch workspace ${workspace}
            obsidian &
            ;;
        kitty|Alacritty|foot)
            hyprctl dispatch workspace ${workspace}
            ${class,,} &
            ;;
        *)
            echo "  Unknown application: ${class}"
            ;;
    esac

    sleep 0.5
done

echo "Session restore complete!"
EOF

chmod +x "${RESTORE_SCRIPT}"

echo "Session saved!"
echo "To restore: ${RESTORE_SCRIPT}"
