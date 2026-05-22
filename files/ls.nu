# List what's in the VM's shared folder. Same view Windows sees at
# \\host.lan\Data.

let ip = (mise run vm:ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" "find /root/windows_shared -mindepth 1 -maxdepth 2 -printf '%p (%s bytes)\n' 2>/dev/null"
