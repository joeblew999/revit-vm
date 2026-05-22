# Interactive SSH on the host Linux VM as root.

let ip = (mise run vm:ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)"
