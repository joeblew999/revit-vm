# Write a .rdp launcher file and open it. dockur defaults: user `Docker`,
# password `admin` (older dockur was empty — type admin when the client asks).

let ip = (mise run vm:ip | str trim)
let rdp = "/tmp/vm-servers.rdp"

$"full address:s:($ip):3389\nusername:s:Docker\nprompt for credentials:i:0\nscreen mode id:i:1\ndesktopwidth:i:1600\ndesktopheight:i:1000\nsession bpp:i:32\naudiomode:i:0\n" | save -f $rdp

print $"wrote ($rdp) — host ($ip):3389, user Docker, password admin"
print "probing port 3389..."
let probe = (^nc -z -w 3 $ip "3389" | complete)
if $probe.exit_code == 0 {
    print "3389 reachable — opening"
} else {
    print "3389 not listening yet (Windows still installing?) — opening anyway"
}
^open $rdp
