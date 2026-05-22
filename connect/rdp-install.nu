# Install / verify a Microsoft RDP client for this OS. Idempotent.
# Dispatches via $nu.os-info.name → "macos" | "linux" | "windows".

def main [] {
    match $nu.os-info.name {
        "macos"   => { install-macos }
        "linux"   => { install-linux }
        "windows" => { install-windows }
        _ => {
            print -e $"unsupported OS: ($nu.os-info.name) — install your own RDP client"
            exit 1
        }
    }
}

def install-macos [] {
    if ("/Applications/Windows App.app" | path exists) {
        print "macOS Windows App already installed."
        return
    }
    # cask installer needs sudo; use a GUI askpass so a native macOS dialog
    # pops (no terminal prompt).
    let askpass = (^mktemp /tmp/askpass.XXXXXX | str trim)
    let body = '#!/bin/bash
osascript -e "tell application \"System Events\" to display dialog \"macOS sudo password (for installing Windows App):\" default answer \"\" with hidden answer with title \"mise rdp:install\"" -e "text returned of result" 2>/dev/null
'
    $body | save -f $askpass
    ^chmod +x $askpass
    with-env { SUDO_ASKPASS: $askpass } { ^brew install --cask windows-app }
    let rc = ($env.LAST_EXIT_CODE? | default 0)
    ^rm -f $askpass
    exit $rc
}

def install-linux [] {
    # Look for any common Linux RDP client. If found, no-op; if not, point
    # the user at a couple of mainstream options. We don't apt/dnf/pacman
    # ourselves — distro choice is the user's.
    let clients = ["xfreerdp", "remmina", "vinagre"]
    let found = ($clients | where {|c| (which $c | length) > 0 })
    if ($found | is-not-empty) {
        print $"Linux RDP client present: ($found | first | get name)"
        return
    }
    print -e "No RDP client found. Install one with your distro's package manager:"
    print -e "  Debian/Ubuntu:  sudo apt install freerdp2-x11   # or remmina"
    print -e "  Fedora:         sudo dnf install freerdp        # or remmina"
    print -e "  Arch:           sudo pacman -S freerdp          # or remmina"
    exit 1
}

def install-windows [] {
    # mstsc.exe ships with every Windows install since XP. Nothing to do.
    print "Windows mstsc.exe is built-in — no install needed."
}
