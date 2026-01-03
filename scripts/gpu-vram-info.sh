#!/usr/bin/env bash
# Display current AMD APU VRAM allocation and usage

echo "=== AMD APU VRAM Information ==="
echo ""

# VRAM Total
vram_total=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
if [ -n "$vram_total" ]; then
    vram_total_mb=$((vram_total / 1024 / 1024))
    echo "VRAM Total:     ${vram_total_mb}MB (${vram_total} bytes)"
else
    echo "VRAM Total:     Unable to read"
fi

# VRAM Used
vram_used=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1)
if [ -n "$vram_used" ]; then
    vram_used_mb=$((vram_used / 1024 / 1024))
    echo "VRAM Used:      ${vram_used_mb}MB (${vram_used} bytes)"

    if [ -n "$vram_total" ] && [ "$vram_total" -gt 0 ]; then
        vram_percent=$((vram_used * 100 / vram_total))
        echo "VRAM Usage:     ${vram_percent}%"
    fi
else
    echo "VRAM Used:      Unable to read"
fi

echo ""

# Visible VRAM (CPU-accessible)
vis_vram_total=$(cat /sys/class/drm/card*/device/mem_info_vis_vram_total 2>/dev/null | head -1)
if [ -n "$vis_vram_total" ]; then
    vis_vram_total_mb=$((vis_vram_total / 1024 / 1024))
    echo "Visible VRAM:   ${vis_vram_total_mb}MB (${vis_vram_total} bytes)"
fi

vis_vram_used=$(cat /sys/class/drm/card*/device/mem_info_vis_vram_used 2>/dev/null | head -1)
if [ -n "$vis_vram_used" ]; then
    vis_vram_used_mb=$((vis_vram_used / 1024 / 1024))
    echo "Visible Used:   ${vis_vram_used_mb}MB (${vis_vram_used} bytes)"
fi

echo ""

# GTT (Graphics Translation Table - system RAM used by GPU)
gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
if [ -n "$gtt_total" ]; then
    gtt_total_mb=$((gtt_total / 1024 / 1024))
    echo "GTT Total:      ${gtt_total_mb}MB (${gtt_total} bytes)"
fi

gtt_used=$(cat /sys/class/drm/card*/device/mem_info_gtt_used 2>/dev/null | head -1)
if [ -n "$gtt_used" ]; then
    gtt_used_mb=$((gtt_used / 1024 / 1024))
    echo "GTT Used:       ${gtt_used_mb}MB (${gtt_used} bytes)"
fi

echo ""
echo "=== Current Module Parameters ==="
if [ -r /sys/module/amdgpu/parameters/vramlimit ]; then
    vramlimit=$(cat /sys/module/amdgpu/parameters/vramlimit 2>/dev/null)
    echo "vramlimit:      $vramlimit"
else
    sudo cat /sys/module/amdgpu/parameters/vramlimit 2>/dev/null | xargs -I {} echo "vramlimit:      {}" || echo "vramlimit:      (requires sudo)"
fi

if [ -r /sys/module/amdgpu/parameters/gttsize ]; then
    gttsize=$(cat /sys/module/amdgpu/parameters/gttsize 2>/dev/null)
    echo "gttsize:        $gttsize"
else
    sudo cat /sys/module/amdgpu/parameters/gttsize 2>/dev/null | xargs -I {} echo "gttsize:        {}" || echo "gttsize:        (requires sudo)"
fi

echo ""
