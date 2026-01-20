#!/usr/bin/env python3
"""
Custom StreamDeck daemon with Home Assistant integration.
Replaces streamdeck-ui with direct hardware control and real-time HA updates.
"""

import asyncio
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFont
from StreamDeck.DeviceManager import DeviceManager
from StreamDeck.ImageHelpers import PILHelper

import aiohttp

# === Configuration ===

HA_URL = "wss://ha.miker.be/api/websocket"
HA_REST_URL = "https://ha.miker.be"
HA_TOKEN_FILE = Path.home() / ".config/home-assistant/token"
ICONS_DIR = Path.home() / "nixos-config/config/streamdeck/icons"

# Font for button text (fallback to default if not found)
FONT_PATH = "/run/current-system/sw/share/X11/fonts/TTF/DejaVuSans.ttf"
FONT_SIZE = 14
FONT_SIZE_SMALL = 12

# Screensaver settings
SCREENSAVER_DIM_TIMEOUT = 150    # 2.5 minutes - dim to 30%
SCREENSAVER_OFF_TIMEOUT = 300    # 5 minutes - screen off


def get_ha_token() -> str:
    if not HA_TOKEN_FILE.exists():
        print(f"ERROR: Token file missing: {HA_TOKEN_FILE}", file=sys.stderr)
        sys.exit(1)
    return HA_TOKEN_FILE.read_text().strip()


# === Button Definitions ===

class Button:
    """Base button class."""
    # Class-level flag to suppress display updates during screensaver
    _display_suspended = False

    def __init__(self, key: int, text: str = "", icon: str = "", bg_color: str = "#000000"):
        self.key = key
        self.text = text
        self.icon = icon
        self.bg_color = bg_color
        self.deck = None

    def render(self) -> Image.Image:
        """Render button image."""
        if self.deck is None:
            return None

        # Create image with background color
        image = PILHelper.create_image(self.deck, background=self.bg_color)
        draw = ImageDraw.Draw(image)

        # Load icon if specified
        if self.icon and Path(self.icon).exists():
            icon_img = Image.open(self.icon).convert("RGBA")
            # Resize icon to fit (leave room for text)
            icon_size = (48, 48) if self.text else (64, 64)
            icon_img = icon_img.resize(icon_size, Image.Resampling.LANCZOS)
            # Center horizontally, offset vertically if text
            x = (image.width - icon_img.width) // 2
            y = 5 if self.text else (image.height - icon_img.height) // 2
            image.paste(icon_img, (x, y), icon_img)

        # Draw text
        if self.text:
            try:
                font = ImageFont.truetype(FONT_PATH, FONT_SIZE_SMALL if "\n" in self.text else FONT_SIZE)
            except OSError:
                font = ImageFont.load_default()

            # Handle multi-line text
            lines = self.text.split("\n")
            y_offset = 55 if self.icon else (image.height // 2 - len(lines) * 8)

            for line in lines:
                bbox = draw.textbbox((0, 0), line, font=font)
                text_width = bbox[2] - bbox[0]
                x = (image.width - text_width) // 2
                draw.text((x, y_offset), line, font=font, fill="white")
                y_offset += 16

        return image

    def update_display(self):
        """Update the physical button display."""
        if self.deck is None or Button._display_suspended:
            return
        image = self.render()
        if image:
            self.deck.set_key_image(self.key, PILHelper.to_native_format(self.deck, image))

    def on_press(self):
        """Called when button is pressed."""
        # Flash effect - brighten background
        self._original_bg = self.bg_color
        self.bg_color = self._brighten_color(self.bg_color)
        self.update_display()

    def on_release(self):
        """Called when button is released."""
        # Restore original background
        if hasattr(self, '_original_bg'):
            self.bg_color = self._original_bg
            self.update_display()

    def _brighten_color(self, hex_color: str) -> str:
        """Brighten a hex color for press feedback."""
        hex_color = hex_color.lstrip('#')
        r, g, b = int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
        # Brighten by 60% for more visible feedback
        r = min(255, int(r + (255 - r) * 0.6))
        g = min(255, int(g + (255 - g) * 0.6))
        b = min(255, int(b + (255 - b) * 0.6))
        return f"#{r:02x}{g:02x}{b:02x}"


class CommandButton(Button):
    """Button that runs a shell command."""
    def __init__(self, key: int, command: str, **kwargs):
        super().__init__(key, **kwargs)
        self.command = command

    def on_press(self):
        super().on_press()
        if self.command:
            subprocess.Popen(self.command, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def on_release(self):
        super().on_release()


class HAButton(Button):
    """Button that calls Home Assistant service."""
    def __init__(self, key: int, service: str, entity_id: str, **kwargs):
        super().__init__(key, **kwargs)
        self.service = service
        self.entity_id = entity_id

    def on_press(self):
        super().on_press()
        token = get_ha_token()
        subprocess.Popen([
            "curl", "-s", "-X", "POST",
            "-H", f"Authorization: Bearer {token}",
            "-H", "Content-Type: application/json",
            "-d", json.dumps({"entity_id": self.entity_id}),
            f"{HA_REST_URL}/api/services/{self.service}"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def on_release(self):
        super().on_release()


class VolumeButton(Button):
    """Volume button with configurable step size."""
    def __init__(self, key: int, entity_id: str, step: float = 0.1, **kwargs):
        super().__init__(key, **kwargs)
        self.entity_id = entity_id
        self.step = step  # +0.1 for up, -0.1 for down

    def on_press(self):
        super().on_press()
        token = get_ha_token()
        # Get current volume and adjust
        try:
            import urllib.request
            req = urllib.request.Request(
                f"{HA_REST_URL}/api/states/{self.entity_id}",
                headers={"Authorization": f"Bearer {token}"}
            )
            with urllib.request.urlopen(req, timeout=2) as resp:
                data = json.loads(resp.read())
                current = data.get("attributes", {}).get("volume_level", 0.5)
                new_vol = max(0.0, min(1.0, current + self.step))
                # Set new volume
                subprocess.Popen([
                    "curl", "-s", "-X", "POST",
                    "-H", f"Authorization: Bearer {token}",
                    "-H", "Content-Type: application/json",
                    "-d", json.dumps({"entity_id": self.entity_id, "volume_level": new_vol}),
                    f"{HA_REST_URL}/api/services/media_player/volume_set"
                ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass  # Fail silently

    def on_release(self):
        super().on_release()


class TRVButton(Button):
    """Climate TRV button with real-time state updates."""
    def __init__(self, key: int, entity_id: str, **kwargs):
        super().__init__(key, **kwargs)
        self.entity_id = entity_id
        self.state = "unknown"
        self.current_temp = None
        self.icon = str(ICONS_DIR / "radiator.png")

    def update_from_ha(self, state_data: dict):
        """Update button state from HA data."""
        self.state = state_data.get("state", "unknown")
        attrs = state_data.get("attributes", {})
        self.current_temp = attrs.get("current_temperature")

        # Update text
        if self.current_temp is not None:
            self.text = f"Office\n{self.current_temp:.1f}°C"
        else:
            self.text = "Office\n--°C"

        # Update color based on state
        if self.state == "heat":
            self.bg_color = "#e65100"  # Orange
        else:
            self.bg_color = "#616161"  # Gray

        self.update_display()

    def on_press(self):
        """Toggle TRV between heat and off."""
        super().on_press()
        token = get_ha_token()
        new_mode = "off" if self.state == "heat" else "heat"
        subprocess.Popen([
            "curl", "-s", "-X", "POST",
            "-H", f"Authorization: Bearer {token}",
            "-H", "Content-Type: application/json",
            "-d", json.dumps({"entity_id": self.entity_id, "hvac_mode": new_mode}),
            f"{HA_REST_URL}/api/services/climate/set_hvac_mode"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def on_release(self):
        super().on_release()


# === Button Layout ===

def create_buttons() -> dict[int, Button]:
    """Create all buttons."""
    return {
        0: CommandButton(0, "playerctl play-pause",
                        text="Play/Pause", icon=str(ICONS_DIR / "playpause.png"), bg_color="#1e88e5"),
        1: CommandButton(1, "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
                        text="Vol -", icon=str(ICONS_DIR / "volume.png"), bg_color="#1e88e5"),
        2: CommandButton(2, "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+",
                        text="Vol +", icon=str(ICONS_DIR / "volume.png"), bg_color="#1e88e5"),
        3: CommandButton(3, "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
                        text="Mute", icon=str(ICONS_DIR / "mute.png"), bg_color="#e53935"),
        4: HAButton(4, "light/toggle", "light.office",
                   text="Office", icon=str(ICONS_DIR / "light.png"), bg_color="#fbc02d"),
        5: TRVButton(5, "climate.shellytrv_office"),
        6: HAButton(6, "script/turn_on", "script.good_night",
                   text="Good Night", icon=str(ICONS_DIR / "sleep.png"), bg_color="#3949ab"),
        7: HAButton(7, "light/turn_off", "all",
                   text="Lights Off", icon=str(ICONS_DIR / "off.png"), bg_color="#c62828"),
        8: VolumeButton(8, "media_player.bureau", step=-0.1,
                       text="Sonos -", icon=str(ICONS_DIR / "vol_down.png"), bg_color="#1db954"),
        9: VolumeButton(9, "media_player.bureau", step=0.1,
                       text="Sonos +", icon=str(ICONS_DIR / "vol_up.png"), bg_color="#1db954"),
        10: CommandButton(10, 'grim -g "$(slurp)" - | wl-copy',
                         text="Screenshot", icon=str(ICONS_DIR / "screenshot.png"), bg_color="#5e35b1"),
        11: CommandButton(11, "loginctl lock-session",
                         text="Lock", icon=str(ICONS_DIR / "lock.png"), bg_color="#00695c"),
        12: CommandButton(12, "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
                         text="Mic Mute", icon=str(ICONS_DIR / "microphone.png"), bg_color="#e53935"),
        13: HAButton(13, "cover/toggle", "cover.curtain_3_3fb4",
                    text="Blinds", icon=str(ICONS_DIR / "blinds.png"), bg_color="#f57f17"),
        14: Button(14),  # Empty
    }


# === Home Assistant WebSocket ===

async def ha_websocket_loop(buttons: dict[int, Button]):
    """Connect to HA websocket and update buttons in real-time."""
    token = get_ha_token()
    msg_id = 1

    # Find TRV buttons to update
    trv_buttons = {b.entity_id: b for b in buttons.values() if isinstance(b, TRVButton)}

    while True:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.ws_connect(HA_URL) as ws:
                    print("Connected to Home Assistant")

                    # Auth
                    msg = await ws.receive_json()
                    if msg.get("type") != "auth_required":
                        continue
                    await ws.send_json({"type": "auth", "access_token": token})
                    msg = await ws.receive_json()
                    if msg.get("type") != "auth_ok":
                        print(f"Auth failed: {msg}")
                        await asyncio.sleep(10)
                        continue

                    print("Authenticated with Home Assistant")

                    # Get initial states
                    await ws.send_json({"id": msg_id, "type": "get_states"})
                    msg_id += 1

                    # Subscribe to state changes
                    await ws.send_json({
                        "id": msg_id,
                        "type": "subscribe_events",
                        "event_type": "state_changed",
                    })
                    msg_id += 1

                    # Process messages
                    async for msg in ws:
                        if msg.type == aiohttp.WSMsgType.TEXT:
                            data = json.loads(msg.data)

                            # Handle get_states response
                            if data.get("type") == "result" and data.get("success"):
                                result = data.get("result", [])
                                if isinstance(result, list):
                                    for state in result:
                                        entity_id = state.get("entity_id")
                                        if entity_id in trv_buttons:
                                            trv_buttons[entity_id].update_from_ha(state)

                            # Handle state change events
                            elif data.get("type") == "event":
                                event = data.get("event", {})
                                if event.get("event_type") == "state_changed":
                                    event_data = event.get("data", {})
                                    entity_id = event_data.get("entity_id")
                                    if entity_id in trv_buttons:
                                        new_state = event_data.get("new_state", {})
                                        trv_buttons[entity_id].update_from_ha(new_state)

                        elif msg.type == aiohttp.WSMsgType.ERROR:
                            break

        except aiohttp.ClientError as e:
            print(f"Connection error: {e}")

        print("Reconnecting in 10s...")
        await asyncio.sleep(10)


# === Main ===

def main():
    # Find StreamDeck
    streamdecks = DeviceManager().enumerate()
    if not streamdecks:
        print("No StreamDeck found!")
        sys.exit(1)

    deck = streamdecks[0]
    deck.open()
    deck.reset()

    print(f"Connected to {deck.deck_type()} ({deck.key_count()} keys)")

    # Set brightness
    deck.set_brightness(100)

    # Pre-create black image for screensaver
    black_image = PILHelper.create_image(deck, background="#000000")
    black_native = PILHelper.to_native_format(deck, black_image)

    # Create buttons
    buttons = create_buttons()
    for button in buttons.values():
        button.deck = deck
        button.update_display()

    # Screensaver state: "awake", "dimmed", "off"
    # Lock protects screensaver state and deck operations
    deck_lock = threading.Lock()
    screensaver = {"state": "awake", "last_activity": time.time()}

    def wake_screen():
        """Wake from screensaver and restore display."""
        with deck_lock:
            if screensaver["state"] != "awake":
                try:
                    Button._display_suspended = False  # Allow display updates
                    deck.set_brightness(100)
                    for button in buttons.values():
                        button.update_display()
                    screensaver["state"] = "awake"  # Only set after success
                except Exception as e:
                    print(f"Wake failed: {e}", file=sys.stderr)
            screensaver["last_activity"] = time.time()

    def dim_screen():
        """Dim the screen."""
        with deck_lock:
            if screensaver["state"] == "awake":
                try:
                    deck.set_brightness(30)
                    screensaver["state"] = "dimmed"
                except Exception as e:
                    print(f"Dim failed: {e}", file=sys.stderr)

    def screen_off():
        """Turn screen off - blank all keys and kill backlight."""
        with deck_lock:
            if screensaver["state"] != "off":
                try:
                    Button._display_suspended = True  # Prevent HA updates drawing over black
                    deck.set_brightness(0)
                    # Set all keys to black for LCD longevity
                    for key in range(deck.key_count()):
                        deck.set_key_image(key, black_native)
                    screensaver["state"] = "off"  # Only set after success
                except Exception as e:
                    print(f"Screen off failed: {e}", file=sys.stderr)

    # Button callback
    def key_callback(deck, key, state):
        # Wake from screensaver on any press
        if screensaver["state"] != "awake":
            if state:  # Only wake on press, not release
                wake_screen()
            return  # Don't trigger button action when waking

        screensaver["last_activity"] = time.time()
        if key in buttons:
            if state:
                buttons[key].on_press()
            else:
                buttons[key].on_release()

    deck.set_key_callback(key_callback)

    # Screensaver check thread
    def screensaver_loop():
        while True:
            time.sleep(10)  # Check every 10 seconds
            idle_time = time.time() - screensaver["last_activity"]
            if screensaver["state"] == "awake" and idle_time > SCREENSAVER_DIM_TIMEOUT:
                dim_screen()
            elif screensaver["state"] == "dimmed" and idle_time > SCREENSAVER_OFF_TIMEOUT:
                screen_off()

    screensaver_thread = threading.Thread(target=screensaver_loop, daemon=True)
    screensaver_thread.start()

    # Run HA websocket in background
    def run_ha_loop():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(ha_websocket_loop(buttons))

    ha_thread = threading.Thread(target=run_ha_loop, daemon=True)
    ha_thread.start()

    # Handle shutdown
    def shutdown(sig, frame):
        print("\nShutting down...")
        deck.reset()
        deck.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print("StreamDeck daemon running. Press Ctrl+C to exit.")

    # Keep main thread alive
    while True:
        try:
            signal.pause()
        except KeyboardInterrupt:
            shutdown(None, None)


if __name__ == "__main__":
    main()
