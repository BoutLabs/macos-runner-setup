#!/usr/bin/env bash
#
# setup-macos-runner.sh — provision a macOS box as a GitHub Actions
# self-hosted runner for Swift/iOS CI, and verify it's actually registered.
#
# Usage:
#   ./setup-macos-runner.sh [--owner <org-or-user>] [--repo <name>]
#   curl -fsSL <raw-url>/setup-macos-runner.sh | bash -s -- --owner BoutLabs
#
# Idempotent: re-running only fixes what's missing. Does NOT register the
# runner for you (that needs a one-time token from GitHub) — it checks
# whether one is configured and, if not, points you at the right page.

set -euo pipefail

OWNER=""
REPO=""        # empty => org-level runner
SIM_DEVICE="iPhone 16"
# User-owned by design: the runner must run as the user who owns the iOS
# simulators (~/Library/Developer/CoreSimulator), via a LaunchAgent — not a
# root daemon — or it can't see them.
RUNNER_DIR="${ACTIONS_RUNNER_DIR:-$HOME/actions-runner}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo)  REPO="$2";  shift 2 ;;
    --device) SIM_DEVICE="$2"; shift 2 ;;
    --runner-dir) RUNNER_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
todo() { printf '  \033[31m→\033[0m %s\n' "$1"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only."; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || warn "Not arm64 — CI labels expect ARM64; Homebrew path assumes /opt/homebrew."

# --- Homebrew -----------------------------------------------------------------
bold "Homebrew"
BREW_PREFIX="/opt/homebrew"; [[ "$(uname -m)" == "arm64" ]] || BREW_PREFIX="/usr/local"
if ! [[ -x "$BREW_PREFIX/bin/brew" ]]; then
  warn "installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
ok "brew on PATH ($BREW_PREFIX)"
# Persist for the non-login shell GitHub Actions uses (this bit us repeatedly).
PROFILE="$HOME/.zprofile"
if ! grep -qs "brew shellenv" "$PROFILE" 2>/dev/null; then
  echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >> "$PROFILE"
  ok "added brew shellenv to $PROFILE"
fi

# --- CLI tools ----------------------------------------------------------------
bold "CI tools"
for tool in swiftlint swiftformat xcbeautify; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else warn "installing $tool"; brew install "$tool"; fi
done

# --- Xcode --------------------------------------------------------------------
bold "Xcode"
if xcodebuild -version >/dev/null 2>&1; then
  ok "$(xcodebuild -version | head -1)"
else
  todo "Xcode not found / not selected. Install Xcode (App Store or https://xcodes.app),"
  todo "then: sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
fi

# --- iOS simulator runtime ----------------------------------------------------
bold "iOS simulator runtime"
if xcrun simctl list runtimes 2>/dev/null | grep -qE "^iOS [0-9]"; then
  ok "$(xcrun simctl list runtimes | grep -E '^iOS [0-9]' | tail -1)"
else
  warn "no iOS runtime — downloading latest (may take a while)"
  sudo xcodebuild -downloadPlatform iOS
fi

# --- iPhone simulator device on the latest runtime ----------------------------
bold "$SIM_DEVICE simulator"
runtime=$(xcrun simctl list runtimes | grep -E "^iOS " | sort -V | tail -1 \
  | grep -oE "com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+")
if xcrun simctl list devices "$runtime" available | grep -q "$SIM_DEVICE ("; then
  ok "$SIM_DEVICE present on newest runtime"
else
  warn "creating $SIM_DEVICE on $runtime"
  xcrun simctl create "$SIM_DEVICE" "$SIM_DEVICE" "$runtime"
fi
# Flag duplicate-device accumulation (made name-based destinations ambiguous in CI).
dupes=$(xcrun simctl list devices available | grep -c "$SIM_DEVICE (" || true)
[[ "$dupes" -gt 1 ]] && warn "$dupes '$SIM_DEVICE' devices exist — CI should target by UDID; consider 'xcrun simctl delete' to prune."

# --- Runner registration check ------------------------------------------------
bold "GitHub Actions runner ($RUNNER_DIR)"
if [[ -f "$RUNNER_DIR/.runner" ]]; then
  ok "runner configured at $RUNNER_DIR"
  warn "ensure it runs as a per-user service: (cd $RUNNER_DIR && ./svc.sh install && ./svc.sh start)"
else
  if [[ -n "$OWNER" ]]; then
    url="https://github.com/organizations/$OWNER/settings/actions/runners/new"
    [[ -n "$REPO" ]] && url="https://github.com/$OWNER/$REPO/settings/actions/runners/new"
    todo "No runner configured. Open: $url"
  else
    todo "No runner configured. Re-run with --owner <org> [--repo <name>] for the exact registration URL."
  fi
  todo "Download + ./config.sh per that page, then add the labels CI expects: self-hosted, macOS, ARM64"
fi

bold "Done."
