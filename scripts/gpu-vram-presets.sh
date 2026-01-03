#!/usr/bin/env bash
# Quick preset scripts for common VRAM allocations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== AMD APU VRAM Quick Presets ==="
echo ""
echo "Current allocation:"
current_vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
if [ -n "$current_vram" ]; then
    current_mb=$((current_vram / 1024 / 1024))
    echo "  ${current_mb}MB"
fi
echo ""
echo "Select a preset:"
echo "  1) 512MB   - Minimal (light desktop use)"
echo "  2) 1GB     - Low (basic gaming/graphics)"
echo "  3) 2GB     - Medium (moderate gaming)"
echo "  4) 4GB     - High (gaming/AI workloads)"
echo "  5) 8GB     - Maximum (heavy AI/graphics)"
echo "  6) Custom amount"
echo "  7) Show current info"
echo "  q) Quit"
echo ""
read -p "Choice: " choice

case $choice in
    1)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 512
        ;;
    2)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 1024
        ;;
    3)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 2048
        ;;
    4)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 4096
        ;;
    5)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 8192
        ;;
    6)
        read -p "Enter VRAM size in MB: " custom_size
        "${SCRIPT_DIR}/gpu-vram-set.sh" "$custom_size"
        ;;
    7)
        "${SCRIPT_DIR}/gpu-vram-info.sh"
        ;;
    q|Q)
        echo "Exiting."
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac
