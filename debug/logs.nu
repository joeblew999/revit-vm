# Tail the dockur container's stdout. Useful when Windows seems stuck.

let ip = (mise run vm:ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" "docker logs --tail 40 windows 2>&1"
