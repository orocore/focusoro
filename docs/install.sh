#!/bin/sh
# Focusoro installer for Linux and macOS.
#
#   curl -fsSL https://focusoro.com/install.sh | sh
#
# Downloads the right binary for this computer from the GitHub release,
# checks its SHA-256, installs it as `focusoro` in ~/.local/bin and, if that
# folder is not on the PATH yet, adds it to the shell's startup file. On Linux
# it also adds Focusoro to the app launcher.
#
# Options (as environment variables):
#   FOCUSORO_VERSION=1.1.0     install that version instead of the latest
#   FOCUSORO_BIN_DIR=/some/dir install there instead of ~/.local/bin
#   FOCUSORO_SITE=https://...  where the launcher icon comes from (tests)
# Uninstall:
#   curl -fsSL https://focusoro.com/install.sh | sh -s -- --uninstall

set -eu

REPO="orocore/focusoro"
VERSION="${FOCUSORO_VERSION:-latest}"
BIN_DIR="${FOCUSORO_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_FILE="$HOME/.local/share/applications/focusoro.desktop"
ICON_FILE="$HOME/.local/share/icons/hicolor/256x256/apps/focusoro.png"
SITE="${FOCUSORO_SITE:-https://focusoro.com}"
RC_MARKER="# Added by the Focusoro installer"

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; GREEN="$(printf '\033[32m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; GREEN=""; RESET=""
fi

# ---- Uninstall --------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$BIN_DIR/focusoro" "$DESKTOP_FILE" "$ICON_FILE"
  say "Focusoro was removed from $BIN_DIR."
  say "Your data was kept. To delete it too, remove:"
  case "$(uname -s)" in
    Darwin) say "  $HOME/Library/Application Support/focusoro" ;;
    *) say "  ${XDG_DATA_HOME:-$HOME/.local/share}/focusoro" ;;
  esac
  exit 0
fi

# ---- Which binary -----------------------------------------------------------
case "$(uname -s)" in
  Linux) os="linux" ;;
  Darwin) os="macos" ;;
  *) fail "this installer is for Linux and macOS. On Windows, see https://focusoro.com" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch="x86_64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) fail "unsupported processor: $(uname -m)" ;;
esac
# Rosetta: a Mac with Apple Silicon running this shell as x86_64.
if [ "$os" = "macos" ] && [ "$arch" = "x86_64" ] &&
   [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
  arch="arm64"
fi
asset="focusoro-$os-$arch"

if [ -n "${FOCUSORO_DOWNLOAD_BASE:-}" ]; then
  base="$FOCUSORO_DOWNLOAD_BASE"  # tests: another source (e.g. file:///...)
elif [ "$VERSION" = "latest" ]; then
  base="https://github.com/$REPO/releases/latest/download"
else
  base="https://github.com/$REPO/releases/download/v${VERSION#v}"
fi

# ---- Download ---------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
else
  fail "curl or wget is needed to download Focusoro"
fi

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t focusoro)"
trap 'rm -rf "$tmp"' EXIT INT TERM

say "Downloading ${BOLD}Focusoro${RESET} ($os, $arch)..."
fetch "$base/$asset" "$tmp/focusoro" || fail "could not download $base/$asset"
fetch "$base/sha256sums.txt" "$tmp/sha256sums.txt" || fail "could not download the checksums"

# ---- Verify -----------------------------------------------------------------
expected="$(grep " $asset\$" "$tmp/sha256sums.txt" | awk '{print $1}')"
[ -n "$expected" ] || fail "no checksum for $asset in this release"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/focusoro" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$tmp/focusoro" | awk '{print $1}')"
fi
[ "$expected" = "$actual" ] || fail "the download is corrupted (checksum mismatch); try again"

# ---- Install ----------------------------------------------------------------
mkdir -p "$BIN_DIR"
chmod 755 "$tmp/focusoro"
mv -f "$tmp/focusoro" "$BIN_DIR/focusoro"
if [ "$os" = "macos" ]; then
  xattr -d com.apple.quarantine "$BIN_DIR/focusoro" 2>/dev/null || true
fi
installed="$("$BIN_DIR/focusoro" --version 2>/dev/null || echo focusoro)"

# App launcher entry (GNOME, KDE, Omarchy...): opens Focusoro in a terminal,
# with the hourglass icon when it downloads (the entry works without it).
if [ "$os" = "linux" ]; then
  mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
  icon_line=""
  if fetch "$SITE/icon.png" "$tmp/icon.png" 2>/dev/null; then
    mv -f "$tmp/icon.png" "$ICON_FILE"
    icon_line="Icon=$ICON_FILE"
  fi
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Focusoro
GenericName=Focus timer
Comment=Pomodoro sessions, focus tracking and goals
Exec=$BIN_DIR/focusoro
Terminal=true
Categories=Utility;Office;
Keywords=pomodoro;focus;timer;study;
$icon_line
EOF
fi

# ---- PATH -------------------------------------------------------------------
on_path=0
case ":$PATH:" in
  *":$BIN_DIR:"*) on_path=1 ;;
esac
added_to=""
if [ "$on_path" = "0" ]; then
  shell_name="$(basename "${SHELL:-sh}")"
  case "$shell_name" in
    zsh) rc="$HOME/.zshrc"; line="export PATH=\"$BIN_DIR:\$PATH\"" ;;
    bash)
      if [ "$os" = "macos" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
      line="export PATH=\"$BIN_DIR:\$PATH\"" ;;
    fish) rc="$HOME/.config/fish/config.fish"; line="fish_add_path \"$BIN_DIR\"" ;;
    *) rc="$HOME/.profile"; line="export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
  if ! grep -qs "$RC_MARKER" "$rc"; then
    mkdir -p "$(dirname "$rc")"
    printf '\n%s\n%s\n' "$RC_MARKER" "$line" >> "$rc"
  fi
  added_to="$rc"
fi

# ---- Done -------------------------------------------------------------------
say ""
say "${GREEN}✓${RESET} ${BOLD}$installed${RESET} installed in $BIN_DIR"
say ""
if [ -n "$added_to" ]; then
  say "Open a ${BOLD}new terminal${RESET} and type:"
else
  say "Type in your terminal:"
fi
say ""
say "    ${BOLD}focusoro${RESET}"
say ""
say "Press h inside the app for every shortcut."
