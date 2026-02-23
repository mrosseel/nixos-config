#!/usr/bin/env python3
"""
Custom StreamDeck daemon with Home Assistant integration.
Replaces streamdeck-ui with direct hardware control and real-time HA updates.
"""

import asyncio
import json
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from StreamDeck.DeviceManager import DeviceManager
from StreamDeck.ImageHelpers import PILHelper

import aiohttp

# === Configuration ===

HA_URL = "wss://ha.miker.be/api/websocket"
HA_TOKEN_FILE = Path.home() / ".config/home-assistant/token"
ICONS_DIR = Path.home() / "nixos-config/config/streamdeck/icons"

# Font for button text (fallback to default if not found)
FONT_PATH = None  # Resolved at startup via fc-match
FONT_SIZE = 14
FONT_SIZE_SMALL = 12

# Screensaver settings
SCREENSAVER_DIM_TIMEOUT = 150    # 2.5 minutes - dim to 30%
SCREENSAVER_OFF_TIMEOUT = 300    # 5 minutes - screen off


def _find_font() -> str:
    """Find a usable TTF font on the system."""
    import subprocess as _sp
    try:
        result = _sp.run(["fc-match", "-f", "%{file}", "DejaVuSans"], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout and Path(result.stdout).exists():
            return result.stdout
    except FileNotFoundError:
        pass
    # Fallback: search common NixOS paths
    for p in Path("/nix/store").glob("*dejavu-fonts*/share/fonts/truetype/DejaVuSans.ttf"):
        return str(p)
    return ""


def get_ha_token() -> str:
    if not HA_TOKEN_FILE.exists():
        print(f"ERROR: Token file missing: {HA_TOKEN_FILE}", file=sys.stderr)
        sys.exit(1)
    return HA_TOKEN_FILE.read_text().strip()


# === WS Command Queue ===
# Button presses from the StreamDeck callback thread put service calls here.
# The async WS loop drains and sends them over the open connection.
_ws_queue: asyncio.Queue | None = None
_ws_loop: asyncio.AbstractEventLoop | None = None


def call_ha_service(domain: str, service: str, **service_data):
    """Queue a service call to be sent over the WS connection."""
    if _ws_loop and _ws_queue is not None:
        _ws_loop.call_soon_threadsafe(
            _ws_queue.put_nowait,
            {"domain": domain, "service": service, "service_data": service_data},
        )


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
        try:
            image = self.render()
            if image:
                self.deck.set_key_image(self.key, PILHelper.to_native_format(self.deck, image))
        except Exception as e:
            print(f"Display error key {self.key}: {e}", file=sys.stderr, flush=True)

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
    """Button that calls Home Assistant service via WS."""
    def __init__(self, key: int, service: str, entity_id: str, **kwargs):
        super().__init__(key, **kwargs)
        # service is "domain/service" e.g. "light/toggle"
        domain, _, svc = service.partition("/")
        self.domain = domain
        self.svc = svc
        self.entity_id = entity_id

    def on_press(self):
        super().on_press()
        call_ha_service(self.domain, self.svc, entity_id=self.entity_id)

    def on_release(self):
        super().on_release()


class VolumeButton(Button):
    """Volume button via WS."""
    def __init__(self, key: int, entity_id: str, direction: str = "up", **kwargs):
        super().__init__(key, **kwargs)
        self.entity_id = entity_id
        self.direction = direction

    def on_press(self):
        super().on_press()
        svc = "volume_up" if self.direction == "up" else "volume_down"
        call_ha_service("media_player", svc, entity_id=self.entity_id)

    def on_release(self):
        super().on_release()


class TRVButton(Button):
    """Climate TRV button with real-time state updates via input_boolean + temp sensor."""
    def __init__(self, key: int, toggle_entity: str, temp_entity: str, label: str = "Office", **kwargs):
        super().__init__(key, **kwargs)
        self.toggle_entity = toggle_entity
        self.temp_entity = temp_entity
        self.label = label
        self.state = "unknown"
        self.current_temp = None
        self.icon = str(ICONS_DIR / "radiator.png")
        self.bg_color = "#37474f"  # Blue-grey (off state) instead of black
        self.text = f"{label}\n--°C"
        # Entities this button watches
        self.watched_entities = {toggle_entity, temp_entity}

    def update_entity(self, entity_id: str, state_data: dict):
        """Update button from a single entity's state change."""
        if entity_id == self.toggle_entity:
            self.state = state_data.get("state", "unknown")
        elif entity_id == self.temp_entity:
            try:
                self.current_temp = float(state_data.get("state", "unknown"))
            except (ValueError, TypeError):
                self.current_temp = None
        self._refresh_display()

    def _refresh_display(self):
        """Update text and color from current state."""
        if self.current_temp is not None:
            self.text = f"{self.label}\n{self.current_temp:.1f}°C"
        else:
            self.text = f"{self.label}\n--°C"

        if self.state == "on":
            self.bg_color = "#e65100"  # Orange when heating
        else:
            self.bg_color = "#37474f"  # Blue-grey when off

        self.update_display()

    def render(self) -> Image.Image:
        """Custom render with smaller icon to fit label + temperature."""
        if self.deck is None:
            return None

        image = PILHelper.create_image(self.deck, background=self.bg_color)
        draw = ImageDraw.Draw(image)

        # Smaller icon at top
        if self.icon and Path(self.icon).exists():
            icon_img = Image.open(self.icon).convert("RGBA")
            icon_img = icon_img.resize((32, 32), Image.Resampling.LANCZOS)
            x = (image.width - 32) // 2
            image.paste(icon_img, (x, 2), icon_img)

        # Two lines of text below icon
        try:
            font = ImageFont.truetype(FONT_PATH, FONT_SIZE_SMALL)
        except OSError:
            font = ImageFont.load_default()

        lines = self.text.split("\n")
        y = 36
        for line in lines:
            bbox = draw.textbbox((0, 0), line, font=font)
            text_width = bbox[2] - bbox[0]
            x = (image.width - text_width) // 2
            draw.text((x, y), line, font=font, fill="white")
            y += 16

        return image

    def on_press(self):
        """Toggle heating via input_boolean over WS."""
        super().on_press()
        call_ha_service("input_boolean", "toggle", entity_id=self.toggle_entity)

    def on_release(self):
        # Re-render with current HA state instead of restoring old bg
        self._refresh_display()


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
        5: TRVButton(5, toggle_entity="input_boolean.climate_office_toggle",
                    temp_entity="sensor.awair_element_54484_temperature", label="Office"),
        6: HAButton(6, "script/turn_on", "script.good_night",
                   text="Good Night", icon=str(ICONS_DIR / "sleep.png"), bg_color="#3949ab"),
        7: HAButton(7, "light/turn_off", "all",
                   text="Lights Off", icon=str(ICONS_DIR / "off.png"), bg_color="#c62828"),
        8: VolumeButton(8, "media_player.bureau", direction="down",
                       text="Sonos -", icon=str(ICONS_DIR / "vol_down.png"), bg_color="#1db954"),
        9: VolumeButton(9, "media_player.bureau", direction="up",
                       text="Sonos +", icon=str(ICONS_DIR / "vol_up.png"), bg_color="#1db954"),
        10: CommandButton(10, 'grim -g "$(slurp)" /home/mike/Downloads/screenshot-$(date +%Y%m%d-%H%M%S).png',
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
    global _ws_queue, _ws_loop
    _ws_loop = asyncio.get_event_loop()
    _ws_queue = asyncio.Queue()

    token = get_ha_token()

    # Build entity -> button mapping for reactive updates
    entity_button_map = {}  # entity_id -> list of TRVButton
    for b in buttons.values():
        if isinstance(b, TRVButton):
            for eid in b.watched_entities:
                entity_button_map.setdefault(eid, []).append(b)

    while True:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.ws_connect(
                    HA_URL, max_msg_size=0, heartbeat=30, receive_timeout=60,
                ) as ws:
                    print("Connected to Home Assistant", flush=True)

                    # Auth
                    msg = await ws.receive_json()
                    if msg.get("type") != "auth_required":
                        print(f"Unexpected initial message: {msg}", flush=True)
                        continue
                    await ws.send_json({"type": "auth", "access_token": token})
                    msg = await ws.receive_json()
                    if msg.get("type") != "auth_ok":
                        print(f"Auth failed: {msg}", flush=True)
                        await asyncio.sleep(10)
                        continue

                    print("Authenticated with Home Assistant", flush=True)

                    # Fresh msg_id per connection
                    msg_id = 1

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

                    async def send_queued_commands():
                        """Send queued service calls over WS."""
                        nonlocal msg_id
                        while True:
                            cmd = await _ws_queue.get()
                            await ws.send_json({
                                "id": msg_id,
                                "type": "call_service",
                                "domain": cmd["domain"],
                                "service": cmd["service"],
                                "service_data": cmd["service_data"],
                            })
                            msg_id += 1

                    async def receive_messages():
                        """Process incoming WS messages."""
                        async for msg in ws:
                            if msg.type == aiohttp.WSMsgType.TEXT:
                                data = json.loads(msg.data)

                                if data.get("type") == "result" and data.get("success"):
                                    result = data.get("result", [])
                                    if isinstance(result, list):
                                        for state in result:
                                            entity_id = state.get("entity_id")
                                            if entity_id in entity_button_map:
                                                for btn in entity_button_map[entity_id]:
                                                    btn.update_entity(entity_id, state)

                                elif data.get("type") == "event":
                                    event = data.get("event", {})
                                    if event.get("event_type") == "state_changed":
                                        event_data = event.get("data", {})
                                        entity_id = event_data.get("entity_id")
                                        if entity_id in entity_button_map:
                                            new_state = event_data.get("new_state", {})
                                            for btn in entity_button_map[entity_id]:
                                                btn.update_entity(entity_id, new_state)

                            elif msg.type in (
                                aiohttp.WSMsgType.ERROR,
                                aiohttp.WSMsgType.CLOSED,
                                aiohttp.WSMsgType.CLOSING,
                            ):
                                print(f"WS closed: {msg.type}", flush=True)
                                return

                    # Run sender and receiver concurrently; if either exits, reconnect
                    done, pending = await asyncio.wait(
                        [
                            asyncio.create_task(send_queued_commands()),
                            asyncio.create_task(receive_messages()),
                        ],
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    for task in pending:
                        task.cancel()
                    for task in done:
                        if task.exception():
                            print(f"WS task error: {task.exception()}", flush=True)

                    print("WS loop exited", flush=True)

        except aiohttp.ClientError as e:
            print(f"Connection error: {e}", flush=True)
        except asyncio.TimeoutError:
            print("WS receive timed out", flush=True)
        except Exception as e:
            import traceback
            print(f"Unexpected error: {e}", flush=True)
            traceback.print_exc()

        print("Reconnecting in 5s...", flush=True)
        await asyncio.sleep(5)


# === Main ===

def main():
    global FONT_PATH
    FONT_PATH = _find_font()
    print(f"Font: {FONT_PATH or 'default'}")

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
        try:
            deck.reset()
            deck.close()
        except Exception:
            pass
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
