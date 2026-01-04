#!/usr/bin/env bash
# Script to configure AMD APU for AI workloads with optimal GTT allocation
# Based on: https://strixhalo.wiki/AI/AI_Capabilities_Overview#memory-limits
# Usage: gpu-ai-mode-set.sh <gtt_size_in_GB>
# Example: gpu-ai-mode-set.sh 64  (for 64GB GTT)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <gtt_size_in_GB>"
    echo ""
    echo "AI Workload Presets for 128GB RAM system:"
    echo "  $0 32   # Light AI (32GB GTT, ~25% of RAM)"
    echo "  $0 64   # Medium AI (64GB GTT, ~50% of RAM)"
    echo "  $0 96   # Heavy AI (96GB GTT, ~75% of RAM)"
    echo "  $0 120  # Maximum AI (120GB GTT, ~94% of RAM)"
    echo ""
    echo "Current GTT allocation:"
    gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
    if [ -n "$gtt_total" ]; then
        gtt_gb=$((gtt_total / 1024 / 1024 / 1024))
        echo "  ${gtt_gb}GB (${gtt_total} bytes)"
    fi
    exit 1
fi

GTT_SIZE_GB=$1
GTT_SIZE_MB=$((GTT_SIZE_GB * 1024))

# Calculate pages_limit (GTT size in 4KB pages)
# Formula: GB * 1024 * 1024 * 1024 / 4096
PAGES_LIMIT=$((GTT_SIZE_GB * 262144))

echo "Configuring GPU for AI workloads:"
echo "  GTT Size: ${GTT_SIZE_GB}GB (${GTT_SIZE_MB}MB)"
echo "  Pages Limit: ${PAGES_LIMIT} pages"
echo ""
echo "⚠️  WARNING: This will reload the GPU driver!"
echo "Your display may flicker or you may need to log back in."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Check if running from graphical session
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    echo "⚠️  Running from graphical session. The session may restart."
    echo "For best results, run this from a TTY (Ctrl+Alt+F2)."
    echo ""
fi

# Unload amdgpu module
echo "Unloading amdgpu module..."
sudo modprobe -r amdgpu || {
    echo "❌ Failed to unload amdgpu. Make sure no applications are using the GPU."
    echo "Stop the display manager first: sudo systemctl stop display-manager"
    exit 1
}

# Reload with AI-optimized parameters
echo "Reloading amdgpu with AI-optimized settings..."
sudo modprobe amdgpu \
  gttsize=${GTT_SIZE_MB} \
  pages_limit=${PAGES_LIMIT}

echo ""
echo "✅ Done! New allocation:"
sleep 1

# Show new GTT allocation
gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
if [ -n "$gtt_total" ]; then
    gtt_gb=$((gtt_total / 1024 / 1024 / 1024))
    gtt_mb=$((gtt_total / 1024 / 1024))
    echo "  GTT Total: ${gtt_gb}GB (${gtt_mb}MB)"
fi

# Show pages_limit from kernel
if [ -r /sys/module/amdgpu/parameters/pages_limit ]; then
    pages=$(cat /sys/module/amdgpu/parameters/pages_limit 2>/dev/null)
    echo "  Pages Limit: ${pages}"
fi

echo ""
echo "📝 AI Model Tips:"
echo "  - Use --ngl 99 (or 999) to load all layers to GPU"
echo "  - Disable mmap for better Vulkan/ROCm performance"
echo "  - GPU layers are 2x faster than CPU (due to memory bandwidth)"
