#!/usr/bin/env bash
# Script to change AMD APU VRAM allocation on the fly
# Usage: gpu-vram-set.sh <size_in_MB>
# Example: gpu-vram-set.sh 2048  (for 2GB)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <vram_size_in_MB>"
    echo "Examples:"
    echo "  $0 512   # 512MB VRAM"
    echo "  $0 1024  # 1GB VRAM"
    echo "  $0 2048  # 2GB VRAM"
    echo "  $0 4096  # 4GB VRAM"
    echo "  $0 8192  # 8GB VRAM"
    echo ""
    echo "Current VRAM allocation:"
    current_vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    if [ -n "$current_vram" ]; then
        current_mb=$((current_vram / 1024 / 1024))
        echo "  ${current_mb}MB (${current_vram} bytes)"
    fi
    exit 1
fi

VRAM_SIZE_MB=$1
VRAM_SIZE_BYTES=$((VRAM_SIZE_MB * 1024 * 1024))

echo "Setting VRAM to ${VRAM_SIZE_MB}MB (${VRAM_SIZE_BYTES} bytes)..."
echo ""
echo "WARNING: This will reload the GPU driver!"
echo "Your display may flicker or you may need to log back in."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Check if we can switch to console
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    echo "NOTE: Running from graphical session. The session may restart."
    echo "For best results, run this from a TTY (Ctrl+Alt+F2)."
    echo ""
fi

# Unload amdgpu module and reload with new parameters
echo "Unloading amdgpu module..."
sudo modprobe -r amdgpu || {
    echo "Failed to unload amdgpu. Make sure no applications are using the GPU."
    echo "You may need to close all GPU-intensive applications first."
    exit 1
}

echo "Reloading amdgpu with ${VRAM_SIZE_MB}MB VRAM..."
sudo modprobe amdgpu vramlimit=${VRAM_SIZE_BYTES}

echo ""
echo "Done! New VRAM allocation:"
sleep 1
new_vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
if [ -n "$new_vram" ]; then
    new_mb=$((new_vram / 1024 / 1024))
    echo "  ${new_mb}MB (${new_vram} bytes)"
fi
