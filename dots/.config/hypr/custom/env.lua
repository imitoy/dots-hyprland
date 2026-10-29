-- Environment variables
-- https://wiki.hyprland.org/Configuring/Environment-variables/

-- Fcitx5
hl.env("INPUT_METHOD", "fcitx")
-- hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("SDL_IM_MODULE", "fcitx")

-- For XWayland
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "aosp-cursors")

-- Nvidia
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("AQ_DRM_DEVICES", "/dev/dri/nvidia-gpu:/dev/dri/intel-gpu")

-- Electron wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Nvidia-specific (GBM backend)
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("WLR_DRM_DEVICES", "/dev/dri/card1")

-- Nvidia optimus/offload
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")

local home_dir = os.getenv("HOME")
local config_dir = home_dir.."/.config"
local cache_dir = home_dir.."/.cache"
local data_dir = home_dir.."/.local/share"
local state_dir = home_dir.."/.local/state"

-- XDG Base Directory
hl.env("XDG_CONFIG_HOME", home_dir.."/.config")
hl.env("XDG_CACHE_HOME", home_dir.."/.cache")
hl.env("XDG_DATA_HOME", home_dir.."/.local/share")
hl.env("XDG_STATE_HOME", home_dir.."/.local/state")

-- Android Tools & Android Studio
hl.env("ANDROID_USER_HOME", home_dir.."/.local/share/android")
hl.env("ANDROID_HOME", "/opt/android-sdk")
hl.env("GRADLE_USER_HOME", home_dir.."/.local/share/android/gradle")
hl.env("STUDIO_GRADLE_JDK", home_dir.."/.local/share/android/studio/jdk")

-- Rust & Cargo
hl.env("CARGO_HOME", home_dir.."/.local/share/cargo")

-- GNUPG
hl.env("GNUPGHOME", home_dir.."/.local/share/gnupg")

-- GTK
hl.env("GTK_RC_FILES", home_dir.."/.config/gtk-1.0/gtkrc")
hl.env("GTK2_RC_FILES", home_dir.."/.config/gtk-2.0/gtkrc:"..home_dir.."/.config/gtk-2.0/gtk.mine")

-- ICE
hl.env("ICEAUTHORITY", home_dir.."/.cache/ICEauthority")

-- Java
hl.env("_JAVA_OPTIONS", "-Djava.util.prefs.userRoot="..home_dir.."/.config/java -Djavafx.cachedir="..data_dir.."/openjfx")
hl.env("LEIN_HOME", data_dir.."/lein")
hl.env("MAVEN_OPTS", "-Dmaven.repo.local="..data_dir.."/maven/repository")
hl.env("MAVEN_ARGS", "--settings "..data_dir.."/maven/settings.xml")

-- NPM
hl.env("NPM_CONFIG_USERCONFIG", home_dir.."/.config/npm/npmrc")

-- Bash
hl.env("HISTFILE", home_dir.."/.local/state/bash/bash_history")

-- Wine
hl.env("WINEPREFIX", home_dir.."/.local/share/wineprefixes/default")

-- w3m
hl.env("W3M_DIR", home_dir.."/.local/state/w3m")

-- wget
hl.env("WGETRC", home_dir.."/.config/wgetrc")

-- ncurses
hl.env("TERMINFO", data_dir.."/terminfo")
hl.env("TERMINFO_DIRS", data_dir.."/terminfo:/usr/share/terminfo")

-- Python
hl.env("PYTHON_HISTORY", state_dir.."/python/history")
hl.env("PYTHONPYCACHEPREFIX", cache_dir.."/python")
hl.env("PYTHONUSERBASE", data_dir.."python")

-- CUDA
hl.env("CUDA_CACHE_PATH", cache_dir.."/nv")

-- Huggingface
hl.env("HF_ENDPOINT", "https://hf-mirror.com")

-- Ollama
hl.env("OLLAMA_MODELS", data_dir.."/ollama/models")

-- Claude Code
hl.env("CLAUDE_CONFIG_DIR", config_dir.."/claude")

-- Codex
hl.env("CODEX_HOME", config_dir.."/codex")
