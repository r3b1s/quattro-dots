#!/usr/bin/env bash
# Build hypr-rdp (native RDP server for Hyprland) from source and install or
# remove the resulting binary on Omarchy/Arch.
#
#   ./hypr-rdp.sh install     clone, build --release --locked, install to /usr/local/bin
#   ./hypr-rdp.sh uninstall   remove the binary and, if we installed it, the PAM service
#
# Upstream: https://github.com/MuNeNICK/hypr-rdp (MIT)
#
# The upstream PKGBUILDs (pkg/aur, pkg/aur-git) are the reference for the
# dependency lists below; this script exists because the AUR packages are not
# the only way to track upstream. Everything is built in a throwaway tmp
# directory, so an interrupted build leaves nothing behind but the build
# scratch space.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: hypr-rdp.sh <command> [options]

Commands:
  install      clone upstream, build with cargo, install to /usr/local/bin
  uninstall    remove the installed binary and the PAM service

Options for install:
  --ref REF    build this branch, tag or commit instead of the default branch
  --no-pam     do not install /etc/pam.d/hypr-rdp (only needed for auth_mode = "pam")
  --yes, -y    do not ask for confirmation
  -h, --help   show this message

Options for uninstall:
  --purge      also remove ~/.config/hypr-rdp (config, TLS cert and key)
  --yes, -y    do not ask for confirmation
  -h, --help   show this message

Options for both:
  KEEP_BUILD=1     keep the tmp clone and target/ directory (default: removed)
  CARGO_TARGET_DIR  reuse an existing cargo target dir instead of the tmp one
EOF
}

repo_url='https://github.com/MuNeNICK/hypr-rdp'
readonly repo_url

# Upstream builds from a release tarball and lands in /usr/bin. We build from a
# clone and follow upstream's README instructions, which install to
# /usr/local/bin: a locally built binary must not shadow a future pacman or AUR
# package of the same name in /usr/bin.
readonly bin_path='/usr/local/bin/hypr-rdp'
readonly pam_path='/etc/pam.d/hypr-rdp'

# Written on install so uninstall knows what it put on the system and does not
# have to guess (or clobber an unrelated file).
readonly manifest_path='/usr/local/share/hypr-rdp/manifest'

# Build-time and runtime packages, mirroring pkg/aur/PKGBUILD plus the headers
# the README's "build from source" section asks for.
#
#   base-devel  cc/ld for the bundled OpenH264 and aws-lc-sys builds
#   clang       libclang, loaded by bindgen for pam-sys
#   cmake       both of those Rust crates build native code through cmake
#   pkgconf     pipewire-0.3, libva and libdrm are found through pkg-config
#   libva       VA-API hardware encoding (default feature)
#   mesa        libdrm headers, used by libva-sys' drm feature
#   pipewire    audio capture (pipewire-0.3 headers)
#   libxkbcommon  keyboard layout handling
#   wayland     wayland client library
#   fuse3       fusermount3, for receiving clipboard files (fuser is pure Rust)
#   libpulse    pactl for the default "redirect" audio routing mode
#   pam         PAM headers for pam-sys/bindgen, and the Linux-password auth mode
readonly build_packages=(base-devel clang cmake pkgconf)
readonly runtime_packages=(libva mesa pipewire libxkbcommon wayland fuse3 libpulse pam)

readonly va_driver_packages=(intel-media-driver libva-mesa-driver)

# Path of the throwaway clone, kept at global scope: the EXIT trap runs after
# install_hypr_rdp has returned, where a local would already be unbound (and
# `set -u` would then abort the cleanup, leaking the whole build tree).
build_root=''

cleanup() {
  if [[ -n "$build_root" && -d "$build_root" ]]; then
    if [[ "${KEEP_BUILD:-0}" == 1 ]]; then
      printf 'Build directory kept at %s\n' "$build_root" >&2
    else
      rm -rf -- "$build_root"
    fi
  fi
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

if ((EUID == 0)); then
  die 'do not run this script as root; cargo must build as your user and sudo is used for the privileged steps'
fi

command -v sudo >/dev/null 2>&1 || die 'sudo is required'

# ---------------------------------------------------------------- toolchain --

# cargo is preferred from wherever the user already has it. If it is missing,
# rust is installed through mise rather than pacman: mise is already the tool
# manager for this machine, and a per-user toolchain needs no root.
#
# mise resolves to a plain install directory, which is used to extend PATH
# instead of `mise activate`: the script may run from a non-interactive shell
# (systemd unit, editor task) where no shell hook has been sourced.
ensure_rust() {
  if command -v cargo >/dev/null 2>&1; then
    note "rust: $(cargo --version)"
    return 0
  fi

  command -v mise >/dev/null 2>&1 ||
    die 'cargo was not found and mise is not installed; install mise (https://mise.run) or rustup, then rerun'

  info 'rust not found; installing it through mise'
  mise install rust@latest

  local rust_dir
  rust_dir="$(mise where rust@latest 2>/dev/null)" ||
    die 'mise could not resolve the rust installation directory'
  [[ -x "$rust_dir/bin/cargo" ]] || die "mise installed rust but $rust_dir/bin/cargo is missing"

  PATH="$rust_dir/bin:$PATH"
  export PATH
  # Child processes (cargo, cc, cmake) must see the same toolchain.
  hash -r 2>/dev/null || true

  note "rust: $(cargo --version) (mise, $rust_dir)"
}

ensure_packages() {
  command -v pacman >/dev/null 2>&1 || die 'pacman not found; this script targets Omarchy/Arch'

  local missing=() package
  for package in "${build_packages[@]}" "${runtime_packages[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
  done

  if ((${#missing[@]})); then
    info "installing missing packages: ${missing[*]}"
    sudo pacman -S --needed --noconfirm -- "${missing[@]}"
  fi
}

# Which VA-API driver to use depends on the GPU, so these are reported rather
# than installed: upstream lists them as optdepends.
check_va_driver() {
  local package
  for package in "${va_driver_packages[@]}"; do
    if pacman -Qq "$package" >/dev/null 2>&1; then
      note "VA-API driver: $package"
      return 0
    fi
  done

  printf '    note: no VA-API driver package found; hypr-rdp will fall back to\n'
  printf '          software H.264 encoding. On Arch install one of:\n'
  printf '            %s (Intel)\n' "${va_driver_packages[0]}"
  printf '            %s (AMD)\n' "${va_driver_packages[1]}"
}

# ------------------------------------------------------------------ install --

# The git dependency on IronRDP is pinned to a commit, so --locked is what
# actually builds the reviewed revision; the clone is shallow only to save
# time, not to skip that pin.
clone_repo() {
  local dest="$1" ref="${2:-}"

  info "cloning $repo_url"
  if [[ -n "$ref" ]]; then
    # --branch only accepts branch and tag names; fetch + checkout also works
    # for a raw commit SHA.
    git clone --depth 1 "$repo_url" "$dest"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout --detach FETCH_HEAD
  else
    git clone --depth 1 "$repo_url" "$dest"
  fi
}

install_hypr_rdp() {
  local ref='' install_pam=1 assume_yes=0

  while (($#)); do
    case "$1" in
      --ref)
        shift || die '--ref needs a branch, tag or commit'
        ref="${1:-}"
        [[ -n "$ref" ]] || die '--ref needs a branch, tag or commit'
        ;;
      --ref=*)
        ref="${1#--ref=}"
        [[ -n "$ref" ]] || die '--ref needs a branch, tag or commit'
        ;;
      --no-pam)
        install_pam=0
        ;;
      -y | --yes)
        assume_yes=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  if ((assume_yes)); then
    printf 'Building hypr-rdp from source and installing it to %s.\n' "$bin_path"
  else
    printf 'This will build hypr-rdp from %s%s\n' "$repo_url" "${ref:+ (ref: $ref)}"
    printf 'and install the binary to %s.\n' "$bin_path"
    ((install_pam)) && printf 'It will also install the PAM service %s.\n' "$pam_path"
    read -r -p 'Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cancelled'
  fi

  ensure_rust
  ensure_packages
  check_va_driver

  local src_dir
  build_root="$(mktemp -d)"
  trap cleanup EXIT
  src_dir="$build_root/hypr-rdp"
  clone_repo "$src_dir" "$ref"

  # Version from the manifest of the tree being built, not from the git
  # description: a clone of a release tag and a clone of main can both build the
  # same Cargo version.
  local version commit
  version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$src_dir/Cargo.toml" | head -1)"
  commit="$(git -C "$src_dir" rev-parse HEAD)"
  info "building hypr-rdp $version ($commit)"

  # OpenH264 and aws-lc-sys compile C/C++ through cmake. cargo passes its own
  # flags to build scripts, and the makepkg hardening flags are not wanted here.
  # CARGO_TARGET_DIR is honoured so an existing cargo cache can be reused
  # between runs; by default everything stays inside the tmp directory.
  local target_dir="${CARGO_TARGET_DIR:-$src_dir/target}"
  ( cd "$src_dir" && env -u CFLAGS -u CXXFLAGS -u LDFLAGS CARGO_TARGET_DIR="$target_dir" cargo build --release --locked )

  [[ -x "$target_dir/release/hypr-rdp" ]] || die "cargo build produced no $target_dir/release/hypr-rdp"

  info "installing $bin_path"
  sudo install -Dm755 "$target_dir/release/hypr-rdp" "$bin_path"

  # Booleans are 0/1, not true/false: `((x))` evaluates its operand as an
  # arithmetic expression, where a bare "false" is an unset variable and trips
  # `set -u`.
  local pam_installed=0 pam_sha256='-' pam_manifest=false
  if ((install_pam)) && install_pam_service "$src_dir"; then
    pam_installed=1
    pam_manifest=true
    pam_sha256="$(sha256sum "$pam_path" | cut -d' ' -f1)"
  fi

  sudo install -Dm644 /dev/stdin "$manifest_path" <<EOF
# Written by scripts/hypr-rdp.sh; read by the uninstall path.
version=$version
commit=$commit
binary=$bin_path
pam=$pam_manifest
pam_path=$pam_path
pam_sha256=$pam_sha256
EOF

  printf '\n'
  info "hypr-rdp $version installed at $bin_path"
  note "binary: $("$bin_path" --version 2>/dev/null || echo '(version not reported)')"
  note "config: ~/.config/hypr-rdp/config.toml"
  note 'start it from your Hyprland session, e.g. hypr-rdp -u user -p pass --bind 0.0.0.0:3389'
  if ((pam_installed)); then
    note 'PAM auth is available; set auth_mode = "pam" in the config to use your login password'
  fi
}

# Only needed for auth_mode = "pam"; the Arch package ships the same file.
# Returns non-zero when nothing was written, so the manifest records that this
# script is not the owner of $pam_path.
install_pam_service() {
  local src_dir="$1" file

  if [[ -e "$pam_path" ]]; then
    note "$pam_path already exists; leaving it alone"
    return 1
  fi

  for file in "$src_dir/pkg/pam/hypr-rdp.arch" "$src_dir/pkg/pam/hypr-rdp.debian"; do
    [[ -f "$file" ]] || continue
    info "installing $pam_path"
    sudo install -Dm644 "$file" "$pam_path"
    return 0
  done

  note 'no PAM service file in the clone; skipping (auth_mode = "pam" will not work)'
  return 1
}

# ---------------------------------------------------------------- uninstall --

read_manifest() {
  [[ -f "$manifest_path" ]] || return 1
  grep -E '^(version|commit|binary|pam|pam_sha256)=' "$manifest_path"
}

# /etc/pam.d/hypr-rdp is only removed when it is byte for byte the file that was
# installed. An edited PAM service is user configuration, even though this
# script put it there.
pam_file_is_ours() {
  local manifest="$1" recorded current

  recorded="$(grep -m1 '^pam_sha256=' <<<"$manifest" | cut -d= -f2-)"
  [[ -n "$recorded" && "$recorded" != '-' ]] || return 1

  current="$(sha256sum "$pam_path" | cut -d' ' -f1)"
  [[ "$recorded" == "$current" ]]
}

uninstall_hypr_rdp() {
  local purge=0 assume_yes=0

  while (($#)); do
    case "$1" in
      --purge)
        purge=1
        ;;
      -y | --yes)
        assume_yes=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  local manifest='' pam_installed=0 config_dir="$HOME/.config/hypr-rdp"
  if manifest="$(read_manifest)" && grep -q '^pam=true$' <<<"$manifest"; then
    pam_installed=1
  fi

  local -a targets=()
  if [[ -e "$bin_path" ]]; then
    targets+=("$bin_path")
  fi
  if ((pam_installed)) && [[ -e "$pam_path" ]]; then
    targets+=("$pam_path")
  fi
  if ((purge)) && [[ -e "$config_dir" ]]; then
    targets+=("$config_dir")
  fi

  if ((${#targets[@]} == 0)) && [[ ! -e "$manifest_path" ]]; then
    info 'nothing to remove'
    return 0
  fi

  if ((${#targets[@]})); then
    printf 'This will remove:\n'
    printf '  %s\n' "${targets[@]}"
  fi
  if [[ -e "$config_dir" && $purge -eq 0 ]]; then
    printf '\n%s is kept; pass --purge to delete it as well.\n' "$config_dir"
    printf 'It holds the config, the generated TLS certificate and key.\n'
  fi
  printf '\nThe rust toolchain and the packages installed for it are left in place.\n'

  if ((assume_yes)); then
    printf 'Continuing.\n'
  else
    read -r -p 'Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die 'cancelled'
  fi

  local target
  for target in "${targets[@]}"; do
    info "removing $target"
    if [[ "$target" == "$pam_path" ]] && ! pam_file_is_ours "$manifest"; then
      printf '    %s was edited after install; keeping it\n' "$target"
      continue
    fi

    case "$target" in
      "$config_dir")
        rm -rf -- "$config_dir"
        ;;
      *)
        sudo rm -f -- "$target"
        ;;
    esac
  done

  sudo rm -f -- "$manifest_path"
  rmdir --ignore-fail-on-non-empty -- /usr/local/share/hypr-rdp 2>/dev/null || true

  info 'hypr-rdp removed'
  note 'packages (fuse3, libva, pipewire, ...) and the rust toolchain were left installed'
}

# --------------------------------------------------------------------- main --

command_name="${1:-}"
[[ $# -gt 0 ]] && shift

case "$command_name" in
  install)
    install_hypr_rdp "$@"
    ;;
  uninstall | remove)
    uninstall_hypr_rdp "$@"
    ;;
  -h | --help | '')
    usage
    [[ -n "$command_name" ]] || exit 2
    ;;
  *)
    usage >&2
    die "unknown command: $command_name"
    ;;
esac