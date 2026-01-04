# StreamDeck Configuration

This directory contains the StreamDeck UI configuration for nixtop.

## Configuration File

- `streamdeck_ui.json` - Main StreamDeck button configuration

## Configured Buttons (Page 0)

### Media Controls
- **Button 0**: Play/Pause - `playerctl play-pause`
- **Button 1**: Volume Down (-5%)
- **Button 2**: Volume Up (+5%)
- **Button 3**: Mute Toggle

### Home Assistant Controls
- **Button 4**: Office Light toggle
- **Button 5**: Living Room light toggle
- **Button 6**: Good Night script
- **Button 7**: All Lights Off

## Setting Up Home Assistant

1. Get your long-lived access token:
   - Go to https://ha.miker.be/profile
   - Scroll to "Long-Lived Access Tokens"
   - Click "Create Token"
   - Copy the token

2. Replace `YOUR_TOKEN_HERE` in `streamdeck_ui.json` with your actual token

3. Update entity IDs to match your Home Assistant entities (e.g., `light.office`, `light.living_room`, etc.)

## Applying Changes

After editing the config:

```bash
# Rebuild to apply symlink
nixsw

# Restart StreamDeck UI
pkill streamdeck-ui && streamdeck-ui &
```

## Adding New Buttons

Edit `streamdeck_ui.json` directly. The structure is:
- Device ID: `DL42K1A04759`
- Pages: `0` and `1` (2 pages total)
- Buttons: `0` through `14` (15 buttons per page)

Each button has:
- `text`: Display text (use `\n` for line breaks)
- `command`: Shell command to execute
- `keys`: Keyboard keys to simulate (alternative to command)
