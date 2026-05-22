# Send a local file/dir TO the VM's shared folder. Lands in Windows at
# \\host.lan\Data\<basename>. Usage: `mise run push -- <local-path>`

def main [path?: string] {
    if ($path == null or ($path | is-empty)) {
        print "usage: mise run push -- <local-path>"
        exit 1
    }
    let ip = (mise run vm:ip | str trim)
    let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
    ^scp -i $key -o StrictHostKeyChecking=accept-new -r $path $"root@($ip):/root/windows_shared/"
    let base = ($path | path basename)
    print $"pushed → \\\\host.lan\\Data\\($base)"
}
