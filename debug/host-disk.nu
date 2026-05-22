# Disk usage on the host VM. Sees Windows qcow2 + shared folder.

let ip = (mise run vm:ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" "df -h /; echo; du -sh /root/windows_storage /root/windows_shared 2>/dev/null"
