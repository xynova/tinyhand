#!/bin/bash
# Try this branch's TinyHand without touching your own install, then remove every trace of it.
#
#   scripts/preview.sh install     build "TinyHand Preview" into dist/ and open it
#   scripts/preview.sh uninstall   quit and delete the preview, its settings and its Accessibility
#                                  permission, and put your TinyHand data folder back as it was
#   scripts/preview.sh status      show what the preview has left on this Mac
#
# The preview has its own name and bundle ID, so its settings are separate from TinyHand's.
# It has no update feed (it can't update itself) and no tinyhand:// links (yours still go to
# your own TinyHand). The one thing both apps share is ~/Library/Application Support/TinyHand
# (custom hands and state.json): install backs it up and uninstall restores it.
# Quit your own TinyHand first: both apps use the same keyboard shortcuts.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

PREVIEW_NAME="TinyHand Preview"
PREVIEW_ID="$BUNDLE_ID.preview"
PREVIEW_APP="$ROOT/dist/$PREVIEW_NAME.app"
DATA_DIR="$HOME/Library/Application Support/TinyHand"
BACKUP_DIR="$HOME/Library/Application Support/TinyHand.before-preview"
NO_DATA_MARK="$HOME/Library/Application Support/TinyHand.preview-had-no-data"

usage() {
    sed -n 2,13p "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

own_tinyhand_running() {
    [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || echo false)" = "true" ]
}

# Ad hoc signing without the hardened runtime. The release signing (sign_app) turns the hardened
# runtime on, which only lets the app load libraries from the same developer team; an ad hoc
# signature has no team, so macOS would refuse the bundled Sparkle framework at launch.
sign_preview() {
    local app="$1"
    local fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    local part
    for part in "$fw/XPCServices/Installer.xpc" "$fw/XPCServices/Downloader.xpc" "$fw/Autoupdate" \
                "$fw/Updater.app" "$app/Contents/Frameworks/Sparkle.framework" "$app"; do
        codesign --force --sign - "$part" 2>/dev/null
    done
    codesign --verify --deep --strict "$app"
}

quit_preview() {
    osascript -e "quit app id \"$PREVIEW_ID\"" >/dev/null 2>&1 || true
    sleep 1
    pkill -f "$PREVIEW_NAME.app/Contents/MacOS/" >/dev/null 2>&1 || true
}

install_preview() {
    if own_tinyhand_running; then
        echo "Your own TinyHand is running. Quit it first (both apps use the same shortcuts), then run this again."
        exit 1
    fi
    if [ -e "$BACKUP_DIR" ] || [ -e "$NO_DATA_MARK" ]; then
        echo "A preview is already installed. Run 'scripts/preview.sh uninstall' first."
        exit 1
    fi

    # Build, bundle and sign first: if any of it fails, nothing on this Mac has changed yet.
    echo "==> Building"
    swift build -c release
    make_bundle .build/release/"$APP_NAME" "$PREVIEW_APP" "0"

    # Its own name and bundle ID, and no tinyhand:// links.
    local plist="$PREVIEW_APP/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "$PREVIEW_ID" "$plist"
    plutil -replace CFBundleName -string "$PREVIEW_NAME" "$plist"
    plutil -replace CFBundleDisplayName -string "$PREVIEW_NAME" "$plist"
    plutil -remove CFBundleURLTypes "$plist"

    echo "==> Signing for this Mac only (ad hoc)"
    sign_preview "$PREVIEW_APP"

    echo "==> Backing up your TinyHand data folder"
    if [ -d "$DATA_DIR" ]; then
        ditto "$DATA_DIR" "$BACKUP_DIR"
        echo "    copied to $BACKUP_DIR"
    else
        mkdir -p "$(dirname "$NO_DATA_MARK")"
        touch "$NO_DATA_MARK"
        echo "    you have none; uninstall will remove the one the preview creates"
    fi

    echo "Installed $PREVIEW_APP"
    if [ "${1:-}" != "--no-open" ]; then
        open "$PREVIEW_APP"
        echo "It will ask for Accessibility permission, the same as TinyHand does."
    fi
    echo "When you're done: scripts/preview.sh uninstall"
}

uninstall_preview() {
    echo "==> Quitting and removing the preview app"
    quit_preview
    rm -rf "$PREVIEW_APP"

    echo "==> Removing its settings and Accessibility permission"
    defaults delete "$PREVIEW_ID" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$PREVIEW_ID" >/dev/null 2>&1 || true

    echo "==> Putting your TinyHand data folder back"
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$DATA_DIR"
        mv "$BACKUP_DIR" "$DATA_DIR"
        echo "    restored from the backup"
    elif [ -e "$NO_DATA_MARK" ]; then
        rm -rf "$DATA_DIR"
        rm -f "$NO_DATA_MARK"
        echo "    removed the folder the preview created (you had none before)"
    else
        echo "    no backup found; left it as it is"
    fi
    echo "Done. Nothing from the preview is left."
}

status_preview() {
    [ -d "$PREVIEW_APP" ] && echo "app:      $PREVIEW_APP" || echo "app:      not installed"
    defaults read "$PREVIEW_ID" >/dev/null 2>&1 && echo "settings: present ($PREVIEW_ID)" || echo "settings: none"
    [ -d "$BACKUP_DIR" ] && echo "backup:   $BACKUP_DIR" || true
    [ -e "$NO_DATA_MARK" ] && echo "backup:   none needed (you had no TinyHand data)" || true
    own_tinyhand_running && echo "note:     your own TinyHand is running" || true
}

case "${1:-}" in
    install) install_preview "${2:-}" ;;
    uninstall) uninstall_preview ;;
    status) status_preview ;;
    *) usage ;;
esac
