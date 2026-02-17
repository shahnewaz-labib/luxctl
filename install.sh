#!/bin/bash
set -e

# luxctl installer
# Usage: curl -fsSL https://raw.githubusercontent.com/thearyanahmed/luxctl/master/install.sh | bash
#
# Downloads a pre-built binary when available (Linux x86_64/aarch64, macOS aarch64).
# Falls back to `cargo install` for unsupported platforms (e.g. macOS Intel).
#
# Environment variables:
#   LUXCTL_VERSION   - pin a specific version (e.g. "v0.8.2"), default: latest
#   INSTALL_DIR      - where to put the binary, default: /usr/local/bin

REPO="thearyanahmed/luxctl"
VERSION="${LUXCTL_VERSION:-}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

info() {
    printf "\033[0;34m==>\033[0m %s\n" "$1"
}

success() {
    printf "\033[0;32m==>\033[0m %s\n" "$1"
}

error() {
    printf "\033[0;31merror:\033[0m %s\n" "$1" >&2
    exit 1
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  PLATFORM="linux" ;;
        Darwin) PLATFORM="macos" ;;
        *)      PLATFORM="unknown" ;;
    esac

    case "$ARCH" in
        x86_64|amd64)   ARCH="x86_64" ;;
        aarch64|arm64)  ARCH="aarch64" ;;
        *)              ARCH="unknown" ;;
    esac
}

# resolve the asset filename for this platform, empty string if no binary available
resolve_asset() {
    case "${PLATFORM}-${ARCH}" in
        linux-x86_64)   ASSET="luxctl-linux-x86_64.tar.gz" ;;
        linux-aarch64)  ASSET="luxctl-linux-aarch64.tar.gz" ;;
        macos-aarch64)  ASSET="luxctl-macos-aarch64.tar.gz" ;;
        *)              ASSET="" ;;
    esac
}

fetch_latest_version() {
    if check_cmd curl; then
        VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' | head -1 | cut -d '"' -f 4)
    elif check_cmd wget; then
        VERSION=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' | head -1 | cut -d '"' -f 4)
    else
        error "curl or wget is required"
    fi

    if [ -z "$VERSION" ]; then
        error "could not determine latest version from GitHub"
    fi
}

download_binary() {
    local url="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    info "Downloading luxctl ${VERSION} (${PLATFORM}/${ARCH})..."

    if check_cmd curl; then
        curl -fsSL "$url" -o "${tmpdir}/luxctl.tar.gz"
    elif check_cmd wget; then
        wget -qO "${tmpdir}/luxctl.tar.gz" "$url"
    fi

    tar -xzf "${tmpdir}/luxctl.tar.gz" -C "$tmpdir"

    # binary inside the tarball is named after the asset (e.g. luxctl-macos-aarch64)
    local bin_name="${ASSET%.tar.gz}"
    if [ -f "${tmpdir}/${bin_name}" ]; then
        mv "${tmpdir}/${bin_name}" "${tmpdir}/luxctl"
    elif [ ! -f "${tmpdir}/luxctl" ]; then
        error "archive did not contain a 'luxctl' or '${bin_name}' binary"
    fi

    chmod +x "${tmpdir}/luxctl"

    # install to INSTALL_DIR, use sudo if needed
    if [ -w "$INSTALL_DIR" ]; then
        mv "${tmpdir}/luxctl" "${INSTALL_DIR}/luxctl"
    else
        info "Writing to ${INSTALL_DIR} requires elevated permissions..."
        sudo mv "${tmpdir}/luxctl" "${INSTALL_DIR}/luxctl"
    fi
}

install_via_cargo() {
    info "No pre-built binary for ${PLATFORM}/${ARCH}, falling back to cargo install..."

    if ! check_cmd cargo; then
        info "Rust not found. Installing via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

        CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"
        if [ -f "$CARGO_BIN/../env" ]; then
            . "$CARGO_BIN/../env"
        fi
        if ! check_cmd cargo; then
            export PATH="$CARGO_BIN:$PATH"
        fi
    fi

    if ! check_cmd cargo; then
        error "cargo not found after installation. Please install Rust manually: https://rustup.rs"
    fi

    local cargo_version="${VERSION#v}"  # strip leading v for crates.io
    if [ -n "$cargo_version" ]; then
        cargo install luxctl --version "$cargo_version"
    else
        cargo install luxctl
    fi
}

main() {
    echo ""
    echo "  luxctl - projectlighthouse.io"
    echo ""

    detect_platform
    resolve_asset

    if [ -z "$VERSION" ]; then
        fetch_latest_version
    fi

    if [ -n "$ASSET" ]; then
        download_binary
    else
        install_via_cargo
    fi

    # verify
    if check_cmd luxctl; then
        INSTALLED_VERSION=$(luxctl --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        success "luxctl ${INSTALLED_VERSION} installed successfully!"
    elif [ -f "${INSTALL_DIR}/luxctl" ]; then
        success "luxctl installed to ${INSTALL_DIR}/luxctl"
        echo ""
        echo "Make sure ${INSTALL_DIR} is in your PATH."
    else
        error "installation failed"
    fi

    echo ""
    echo "Get started:"
    echo "  luxctl auth --token <YOUR_TOKEN>"
    echo "  luxctl doctor"
    echo ""
}

main
