#!/usr/bin/env bash
# GPU mode selector - switch between desktop and AI workload configurations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== GPU Configuration Mode Selector ==="
echo ""
echo "Current allocation:"
gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
if [ -n "$gtt_total" ]; then
    gtt_gb=$((gtt_total / 1024 / 1024 / 1024))
    echo "  GTT: ${gtt_gb}GB"
fi
echo ""
echo "Select mode:"
echo ""
echo "Desktop Modes (VRAM-focused):"
echo "  1) Minimal     - 512MB   (light desktop use)"
echo "  2) Low         - 2GB     (basic tasks)"
echo "  3) Medium      - 4GB     (moderate use)"
echo "  4) High        - 8GB     (gaming/graphics)"
echo ""
echo "AI Workload Modes (GTT-focused, optimized for model loading):"
echo "  5) Light AI    - 32GB GTT  (~25% of 128GB RAM)"
echo "  6) Medium AI   - 64GB GTT  (~50% of 128GB RAM)"
echo "  7) Heavy AI    - 96GB GTT  (~75% of 128GB RAM)"
echo "  8) Maximum AI  - 120GB GTT (~94% of 128GB RAM)"
echo ""
echo "  9) Custom VRAM amount"
echo "  0) Custom AI GTT amount"
echo "  i) Show current info"
echo "  q) Quit"
echo ""
read -p "Choice: " choice

case $choice in
    1)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 512
        ;;
    2)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 2048
        ;;
    3)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 4096
        ;;
    4)
        "${SCRIPT_DIR}/gpu-vram-set.sh" 8192
        ;;
    5)
        "${SCRIPT_DIR}/gpu-ai-mode-set.sh" 32
        ;;
    6)
        "${SCRIPT_DIR}/gpu-ai-mode-set.sh" 64
        ;;
    7)
        "${SCRIPT_DIR}/gpu-ai-mode-set.sh" 96
        ;;
    8)
        "${SCRIPT_DIR}/gpu-ai-mode-set.sh" 120
        ;;
    9)
        read -p "Enter VRAM size in MB: " custom_size
        "${SCRIPT_DIR}/gpu-vram-set.sh" "$custom_size"
        ;;
    0)
        read -p "Enter GTT size in GB: " custom_gtt
        "${SCRIPT_DIR}/gpu-ai-mode-set.sh" "$custom_gtt"
        ;;
    i|I)
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
