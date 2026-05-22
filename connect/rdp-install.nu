# Install Microsoft's macOS RDP client ("Windows App") via Homebrew cask.
# One-time per machine. The cask runs a .pkg installer that needs sudo;
# uses an askpass helper so a native macOS password dialog pops (no
# terminal prompt). Idempotent.

if ("/Applications/Windows App.app" | path exists) {
    print "Windows App already installed."
    exit 0
}

let askpass = (^mktemp /tmp/askpass.XXXXXX | str trim)
let askpass_body = '#!/bin/bash
osascript -e "tell application \"System Events\" to display dialog \"macOS sudo password (for installing Windows App):\" default answer \"\" with hidden answer with title \"mise rdp:install\"" -e "text returned of result" 2>/dev/null
'
$askpass_body | save -f $askpass
^chmod +x $askpass

with-env { SUDO_ASKPASS: $askpass } {
    ^brew install --cask windows-app
}

let rc = ($env.LAST_EXIT_CODE? | default 0)
^rm -f $askpass
exit $rc
