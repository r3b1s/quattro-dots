-- Host-local post-default GPU environment override (installed by opt/gpu-session/install.sh).
-- Loaded after default.hypr.omarchy so default/hypr/nvidia.lua does not override
-- Mesa/radeonsi settings when the desktop runs isolated on the RX 580.
local gpu_session = os.getenv("QUATTRO_GPU_SESSION") or "rx580"

if gpu_session == "rx580" then
  hl.env("LIBVA_DRIVER_NAME", "radeonsi")
  hl.env("VDPAU_DRIVER", "radeonsi")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
  hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
  hl.env("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/radeon_icd.json")
  hl.env("NVD_BACKEND", "")
elseif gpu_session == "rtx3070" then
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  hl.env("VDPAU_DRIVER", "")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/10_nvidia.json")
  hl.env("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/nvidia_icd.json")
  hl.env("NVD_BACKEND", "direct")
end
