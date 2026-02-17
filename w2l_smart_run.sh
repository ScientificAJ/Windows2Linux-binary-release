#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W2L_BIN="${W2L_BIN:-$SCRIPT_DIR/window2linux}"
MAX_ATTEMPTS=3
TIMEOUT_SECONDS=180
MODE="auto"
USE_GAMESCOPE=0
GAMESCOPE_RES="1920x1080"
GAMESCOPE_FPS=144
SETUP_ONLY=0
SKIP_INSTALL=0
TARGET=""

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./w2l_smart_run.sh [options] [target.exe|target.msi]

Examples:
  ./w2l_smart_run.sh --setup-only
  ./w2l_smart_run.sh "$HOME/.wine/drive_c/Program Files/Microsoft Office/root/Office16/POWERPNT.EXE"

Options:
  --setup-only             Install/check dependencies only; do not launch an app.
  --no-install             Skip dependency installation.
  --binary PATH            Path to window2linux binary (default: ./window2linux).
  --mode MODE              Execution mode: auto|install|play (default: auto).
  --max-attempts N         Window2Linux attempts per run (default: 3).
  --timeout-seconds N      Timeout per attempt (default: 180).
  --use-gamescope          Enable gamescope wrapper.
  --gamescope-res WxH      Gamescope resolution (default: 1920x1080).
  --gamescope-fps N        Gamescope refresh rate (default: 144).
  -h, --help               Show this help.
USAGE
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    if sudo -n true >/dev/null 2>&1; then
      sudo "$@"
    else
      die "Root privileges are required for package installation. Re-run with: sudo ./w2l_smart_run.sh --setup-only"
    fi
  fi
}

detect_pm() {
  if has_cmd apt-get; then
    echo apt
  elif has_cmd dnf; then
    echo dnf
  elif has_cmd pacman; then
    echo pacman
  elif has_cmd zypper; then
    echo zypper
  else
    echo unknown
  fi
}

have_proton() {
  if has_cmd proton || has_cmd proton-run || has_cmd proton-ge; then
    return 0
  fi

  local roots=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  )

  local root
  for root in "${roots[@]}"; do
    if compgen -G "$root/steamapps/common/Proton */proton" >/dev/null; then
      return 0
    fi
    if compgen -G "$root/steamapps/common/Proton-*GE*/proton" >/dev/null; then
      return 0
    fi
  done

  return 1
}

install_deps() {
  if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    warn "Dependency installation skipped (--no-install)."
    return 1
  fi

  local pm
  pm="$(detect_pm)"

  case "$pm" in
    apt)
      log "Using apt to install dependencies..."
      run_as_root apt-get update
      run_as_root apt-get install -y wine winetricks cabextract p7zip-full ca-certificates curl
      run_as_root apt-get install -y gamescope || warn "gamescope package install skipped."
      if ! have_proton; then
        log "Proton not detected. Installing Steam packages to provide Proton runtime..."
        run_as_root apt-get install -y steam-installer || run_as_root apt-get install -y steam || true
      fi
      ;;
    dnf)
      log "Using dnf to install dependencies..."
      run_as_root dnf install -y wine winetricks cabextract p7zip p7zip-plugins curl
      run_as_root dnf install -y gamescope || warn "gamescope package install skipped."
      if ! have_proton; then
        run_as_root dnf install -y steam || true
      fi
      ;;
    pacman)
      log "Using pacman to install dependencies..."
      run_as_root pacman -Sy --needed --noconfirm wine winetricks cabextract p7zip curl
      run_as_root pacman -Sy --needed --noconfirm gamescope || warn "gamescope package install skipped."
      if ! have_proton; then
        run_as_root pacman -Sy --needed --noconfirm steam || true
      fi
      ;;
    zypper)
      log "Using zypper to install dependencies..."
      run_as_root zypper --non-interactive install wine winetricks cabextract p7zip curl
      run_as_root zypper --non-interactive install gamescope || warn "gamescope package install skipped."
      if ! have_proton; then
        run_as_root zypper --non-interactive install steam || true
      fi
      ;;
    *)
      warn "Unsupported package manager. Please install manually: wine, winetricks, and Steam/Proton."
      ;;
  esac
}

print_runner_status() {
  "$W2L_BIN" inspect runners --json || true
}

print_gamescope_status() {
  if has_cmd gamescope; then
    log "gamescope available: $(command -v gamescope)"
  else
    warn "gamescope not found on PATH."
  fi
}

find_target_if_missing() {
  if [[ -n "$TARGET" ]]; then
    return 0
  fi

  local candidates=(
    "$HOME/.wine/drive_c/Program Files/Microsoft Office/root/Office16/POWERPNT.EXE"
    "$HOME/.wine/drive_c/Program Files (x86)/Microsoft Office/root/Office16/POWERPNT.EXE"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      TARGET="$candidate"
      log "Auto-detected PowerPoint executable: $TARGET"
      return 0
    fi
  done

  if [[ -d "$HOME/.wine/drive_c" ]]; then
    local detected
    detected="$(find "$HOME/.wine/drive_c" -type f -iname 'POWERPNT.EXE' 2>/dev/null | head -n 1 || true)"
    if [[ -n "$detected" ]]; then
      TARGET="$detected"
      log "Detected PowerPoint executable by search: $TARGET"
      return 0
    fi
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup-only)
      SETUP_ONLY=1
      shift
      ;;
    --no-install)
      SKIP_INSTALL=1
      shift
      ;;
    --binary)
      [[ $# -lt 2 ]] && die "Missing value for --binary"
      W2L_BIN="$2"
      shift 2
      ;;
    --mode)
      [[ $# -lt 2 ]] && die "Missing value for --mode"
      MODE="$2"
      shift 2
      ;;
    --max-attempts)
      [[ $# -lt 2 ]] && die "Missing value for --max-attempts"
      MAX_ATTEMPTS="$2"
      shift 2
      ;;
    --timeout-seconds)
      [[ $# -lt 2 ]] && die "Missing value for --timeout-seconds"
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --use-gamescope)
      USE_GAMESCOPE=1
      shift
      ;;
    --gamescope-res)
      [[ $# -lt 2 ]] && die "Missing value for --gamescope-res"
      GAMESCOPE_RES="$2"
      shift 2
      ;;
    --gamescope-fps)
      [[ $# -lt 2 ]] && die "Missing value for --gamescope-fps"
      GAMESCOPE_FPS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ "$MODE" =~ ^(auto|install|play)$ ]] || die "--mode must be one of: auto, install, play"
[[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || die "--max-attempts must be an integer"
[[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "--timeout-seconds must be an integer"
[[ "$GAMESCOPE_FPS" =~ ^[0-9]+$ ]] || die "--gamescope-fps must be an integer"

if [[ ! -x "$W2L_BIN" ]]; then
  die "Binary not found or not executable: $W2L_BIN"
fi

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  install_deps || true
else
  warn "Skipping dependency installation (--no-install)."
fi

print_runner_status
print_gamescope_status

if [[ "$SETUP_ONLY" -eq 1 ]]; then
  log "Setup checks finished."
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  find_target_if_missing || die "No target provided and auto-detection failed. Pass a .exe/.msi path."
fi

if [[ ! -f "$TARGET" ]]; then
  die "Target does not exist: $TARGET"
fi

run_args=(
  run
  "$TARGET"
  --execute
  --mode "$MODE"
  --max-attempts "$MAX_ATTEMPTS"
  --timeout-seconds "$TIMEOUT_SECONDS"
)
if [[ "$USE_GAMESCOPE" -eq 1 ]]; then
  run_args+=(--use-gamescope --gamescope-res "$GAMESCOPE_RES" --gamescope-fps "$GAMESCOPE_FPS")
fi

log "Launching Window2Linux binary..."
"$W2L_BIN" "${run_args[@]}"
