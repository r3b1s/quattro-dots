# `opt/` — Host-Specific Opt-In Configurations

The `opt/` directory houses hardware-specific or host-specific configurations, utilities, and Omarchy shell plugins that are **not** installed automatically by the top-level `./install.sh`. Users opt in explicitly on the hosts that need them.

## Modules

### `opt/gpu-session/`

Dual-GPU session switcher and RTX 3070 AI VRAM isolation stack for desktop hosts with both an AMD Radeon RX 580 (`04:00.0`) and an NVIDIA GeForce RTX 3070 (`2b:00.0`).

- **`bin/gpu-session`** → `~/.local/bin/gpu-session` (`0755`):
  - Idempotent CLI (`gpu-session [status [--json] | rx580 | rtx3070] [-n|--dry-run]`).
  - Manages `~/.config/uwsm/env.d/10-gpu.conf` so `AQ_DRM_DEVICES`, EGL, GLX, VA-API, VDPAU, and Vulkan select the active display GPU while keeping the `nvidia` kernel module loaded for CUDA/AI workloads.
  - Includes a sysfs connected-display safety fallback in `10-gpu.conf`: if DisplayPort cables are moved to the other card while powered off without staging a switch first, UWSM falls back to the GPU with connected displays.
- **`plugin/t.gpu-session/`** → `~/.config/omarchy/plugins/t.gpu-session/` (`0644`):
  - Omarchy Quickshell `KeyboardPanel` bar widget (`t.gpu-session`) showing active display GPU, live RTX 3070 VRAM usage, `/dev/nvidia*` + `/dev/dri/card*` desktop process isolation, and next-boot GPU switcher buttons.
- **`hypr/gpu.lua`** → `~/.config/hypr/gpu.lua` (`0644`):
  - Optional post-default Hyprland GPU override module loaded conditionally by `hypr/hyprland.lua` via `require("default.hypr.require_optional").module("hypr.gpu")`, ensuring `default/hypr/nvidia.lua` does not override Mesa/radeonsi settings when `QUATTRO_GPU_SESSION=rx580`.
- **`install.sh`**:
  - Idempotent opt-in installer supporting `-n|--dry-run` and `--remove`.
  - Installs `gpu-session`, `t.gpu-session`, and `~/.config/hypr/gpu.lua` using direct file copies (no symlinks), initializes `~/.config/uwsm/env.d/10-gpu.conf`, ensures `hypr/hyprland.lua` loads `hypr.gpu`, updates local `~/.config/hypr/monitors.lua` to port-independent `desc:` monitor matching, rescans plugins, and places `t.gpu-session` on the bar (`right` section).
