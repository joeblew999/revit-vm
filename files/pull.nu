# Pull a file/dir FROM the VM's shared folder. Usage:
# `mise run pull -- <name>` — file lands in current dir.

def main [name?: string] {
    if ($name == null or ($name | is-empty)) {
        print "usage: mise run pull -- <remote-name>"
        exit 1
    }
    let ip = (mise run vm:ip | str trim)
    let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
    ^scp -i $key -o StrictHostKeyChecking=accept-new -r $"root@($ip):/root/windows_shared/($name)" .
    print $"pulled ← ./($name)"
}
