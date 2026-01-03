{ pkgs, inputs, ... }:
let
  # GPU VRAM management scripts
  gpu-vram-set = pkgs.writeShellScriptBin "gpu-vram-set" ''
    # Script to change AMD APU VRAM allocation on the fly
    # Usage: gpu-vram-set <size_in_MB>
    # Example: gpu-vram-set 2048  (for 2GB)

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
            echo "  ''${current_mb}MB (''${current_vram} bytes)"
        fi
        exit 1
    fi

    VRAM_SIZE_MB=$1
    VRAM_SIZE_BYTES=$((VRAM_SIZE_MB * 1024 * 1024))

    echo "Setting VRAM to ''${VRAM_SIZE_MB}MB (''${VRAM_SIZE_BYTES} bytes)..."
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
    sudo ${pkgs.kmod}/bin/modprobe -r amdgpu || {
        echo "Failed to unload amdgpu. Make sure no applications are using the GPU."
        echo "You may need to close all GPU-intensive applications first."
        exit 1
    }

    echo "Reloading amdgpu with ''${VRAM_SIZE_MB}MB VRAM..."
    sudo ${pkgs.kmod}/bin/modprobe amdgpu vramlimit=''${VRAM_SIZE_BYTES}

    echo ""
    echo "Done! New VRAM allocation:"
    sleep 1
    new_vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    if [ -n "$new_vram" ]; then
        new_mb=$((new_vram / 1024 / 1024))
        echo "  ''${new_mb}MB (''${new_vram} bytes)"
    fi
  '';

  gpu-vram-info = pkgs.writeShellScriptBin "gpu-vram-info" ''
    # Display current AMD APU VRAM allocation and usage

    echo "=== AMD APU VRAM Information ==="
    echo ""

    # VRAM Total
    vram_total=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    if [ -n "$vram_total" ]; then
        vram_total_mb=$((vram_total / 1024 / 1024))
        echo "VRAM Total:     ''${vram_total_mb}MB (''${vram_total} bytes)"
    else
        echo "VRAM Total:     Unable to read"
    fi

    # VRAM Used
    vram_used=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1)
    if [ -n "$vram_used" ]; then
        vram_used_mb=$((vram_used / 1024 / 1024))
        echo "VRAM Used:      ''${vram_used_mb}MB (''${vram_used} bytes)"

        if [ -n "$vram_total" ] && [ "$vram_total" -gt 0 ]; then
            vram_percent=$((vram_used * 100 / vram_total))
            echo "VRAM Usage:     ''${vram_percent}%"
        fi
    else
        echo "VRAM Used:      Unable to read"
    fi

    echo ""

    # Visible VRAM (CPU-accessible)
    vis_vram_total=$(cat /sys/class/drm/card*/device/mem_info_vis_vram_total 2>/dev/null | head -1)
    if [ -n "$vis_vram_total" ]; then
        vis_vram_total_mb=$((vis_vram_total / 1024 / 1024))
        echo "Visible VRAM:   ''${vis_vram_total_mb}MB (''${vis_vram_total} bytes)"
    fi

    vis_vram_used=$(cat /sys/class/drm/card*/device/mem_info_vis_vram_used 2>/dev/null | head -1)
    if [ -n "$vis_vram_used" ]; then
        vis_vram_used_mb=$((vis_vram_used / 1024 / 1024))
        echo "Visible Used:   ''${vis_vram_used_mb}MB (''${vis_vram_used} bytes)"
    fi

    echo ""

    # GTT (Graphics Translation Table - system RAM used by GPU)
    gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
    if [ -n "$gtt_total" ]; then
        gtt_total_mb=$((gtt_total / 1024 / 1024))
        echo "GTT Total:      ''${gtt_total_mb}MB (''${gtt_total} bytes)"
    fi

    gtt_used=$(cat /sys/class/drm/card*/device/mem_info_gtt_used 2>/dev/null | head -1)
    if [ -n "$gtt_used" ]; then
        gtt_used_mb=$((gtt_used / 1024 / 1024))
        echo "GTT Used:       ''${gtt_used_mb}MB (''${gtt_used} bytes)"
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
  '';

  gpu-vram-presets = pkgs.writeShellScriptBin "gpu-vram-presets" ''
    # Quick preset scripts for common VRAM allocations

    echo "=== AMD APU VRAM Quick Presets ==="
    echo ""
    echo "Current allocation:"
    current_vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
    if [ -n "$current_vram" ]; then
        current_mb=$((current_vram / 1024 / 1024))
        echo "  ''${current_mb}MB"
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
            ${gpu-vram-set}/bin/gpu-vram-set 512
            ;;
        2)
            ${gpu-vram-set}/bin/gpu-vram-set 1024
            ;;
        3)
            ${gpu-vram-set}/bin/gpu-vram-set 2048
            ;;
        4)
            ${gpu-vram-set}/bin/gpu-vram-set 4096
            ;;
        5)
            ${gpu-vram-set}/bin/gpu-vram-set 8192
            ;;
        6)
            read -p "Enter VRAM size in MB: " custom_size
            ${gpu-vram-set}/bin/gpu-vram-set "$custom_size"
            ;;
        7)
            ${gpu-vram-info}/bin/gpu-vram-info
            ;;
        q|Q)
            echo "Exiting."
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
  '';
in
{
  environment.systemPackages = [
    pkgs.claude-code
    # pkgs.gemini-cli  # Disabled due to CVE-2024-23342 in ecdsa dependency
    pkgs.ollama
    # GPU VRAM management tools
    gpu-vram-set
    gpu-vram-info
    gpu-vram-presets
  ];

  # Ollama service with AMD GPU acceleration
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;  # Use ollama-cuda for NVIDIA, ollama for CPU-only
  };

  # Open WebUI - Web interface for Ollama
  # Temporarily disabled due to beautifulsoup4 version conflict
  # services.open-webui = {
  #   enable = true;
  #   port = 8080;
  #   environment = {
  #     OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
  #   };
  # };
}

