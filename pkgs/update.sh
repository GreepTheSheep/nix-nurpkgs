#!/usr/bin/env bash
# Updates the local packages in the pkgs/ directory.
# Usage: ./pkgs/update.sh [package-name] [version]
#
# Examples:
#   ./pkgs/update.sh                     # updates ALL packages in pkgs/
#   ./pkgs/update.sh nxapi               # updates nxapi only (latest version)
#   ./pkgs/update.sh nxapi 1.7.0         # nxapi to a specific version
#
# Requirements: nix-update (available via `nix run nixpkgs#nix-update`)
#               jq, nix-prefetch-url, python3

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKGS_DIR="$REPO_ROOT/pkgs"

# --- Lists the available packages (one per subdirectory with a default.nix) ---
list_packages() {
  for d in "$PKGS_DIR"/*/; do
    [ -f "$d/default.nix" ] && basename "$d"
  done
}

# --- Updates a given package ---
update_package() {
  local pkg_name="$1"
  local version_arg=""

  if [ $# -eq 2 ]; then
    version_arg="--version $2"
    echo "Target version: $2"
  else
    echo "Target version: latest available"
  fi

  local pkg_dir="$PKGS_DIR/$pkg_name"
  if [ ! -d "$pkg_dir" ]; then
    echo "Error: directory $pkg_dir does not exist"
    return 1
  fi

  echo "=== Updating: $pkg_name ==="

  # Detects package-specific quirks
  local needs_insecure=false
  for f in "$pkg_dir"/*.nix; do
    if grep -qE "electron_[0-9]+|nodejs_[0-9]+" "$f"; then
      needs_insecure=true
      break
    fi
  done

  local nix_update_args="--flake $version_arg"
  local build_cmd="nix build .#$pkg_name --no-link --print-out-paths"

  if [ "$needs_insecure" = true ]; then
    echo "  (insecure dependencies -> NIXPKGS_ALLOW_INSECURE=1)"
    # nix-update does not accept --impure (it uses nix-instantiate, which
    # already reads NIXPKGS_ALLOW_INSECURE from the environment).
    build_cmd="NIXPKGS_ALLOW_INSECURE=1 $build_cmd --impure"
    export NIXPKGS_ALLOW_INSECURE=1
  fi

  # nix-update updates version + hashes automatically
  echo "--- nix-update ---"
  nix run nixpkgs#nix-update -- $nix_update_args "$pkg_name" || {
    echo "nix-update failed for $pkg_name"
    return 1
  }

  # Verifies the build
  echo "--- Build check ---"
  eval "$build_cmd" 2>&1 | tail -5 || {
    echo "Build failed for $pkg_name"
    return 1
  }

  echo "OK: $pkg_name"
  echo ""
}

# --- Argument parsing ---
if [ $# -eq 0 ]; then
  # No argument: update all packages
  packages=$(list_packages)
  if [ -z "$packages" ]; then
    echo "No package found in $PKGS_DIR"
    exit 1
  fi

  echo "Updating all packages:"
  echo "$packages" | sed 's/^/  /'
  echo ""

  failed=()
  for pkg in $packages; do
    if ! update_package "$pkg"; then
      failed+=("$pkg")
    fi
  done

  echo "=== Summary ==="
  if [ ${#failed[@]} -eq 0 ]; then
    echo "All packages updated successfully."
  else
    echo "Failed for: ${failed[*]}"
    exit 1
  fi
elif [ $# -eq 1 ]; then
  update_package "$1"
elif [ $# -eq 2 ]; then
  update_package "$1" "$2"
else
  echo "Usage: $0 [package-name] [version]"
  echo ""
  echo "Packages available in pkgs/:"
  list_packages | sed 's/^/  /'
  exit 1
fi