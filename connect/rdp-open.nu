# Write a .rdp launcher file and open it with the host OS's default opener.
# dockur defaults: user `Docker`, password `admin`.

def os-open [path: string] {
    match $nu.os-info.name {
        "macos"   => { ^open $path }
        "linux"   => { ^xdg-open $path }
        "windows" => { ^cmd /c start "" $path }
        _ => {
            print -e $"don't know how to open files on ($nu.os-info.name) — file is at ($path)"
            exit 1
        }
    }
}

# Cross-platform TCP probe: nc on unix, Test-NetConnection on Windows.
def port-open [host: string, port: int] {
    if $nu.os-info.name == "windows" {
        let r = (^powershell -Command $"\(Test-NetConnection -ComputerName ($host) -Port ($port) -WarningAction SilentlyContinue\).TcpTestSucceeded" | complete)
        ($r.stdout | str trim | str downcase) == "true"
    } else {
        let r = (^nc -z -w 3 $host ($port | into string) | complete)
        $r.exit_code == 0
    }
}

let ip = (match $env.VM_PROVIDER {
    "hetzner" => (nu providers/hetzner/ip.nu),
    "vultr"   => (nu providers/vultr/ip.nu),
    _ => { print -e $"VM_PROVIDER must be hetzner|vultr"; exit 1 }
} | str trim)

let tmp = (if $nu.os-info.name == "windows" { $env.TEMP } else { "/tmp" })
let rdp = $"($tmp)/vm-servers.rdp"

$"full address:s:($ip):3389\nusername:s:Docker\nprompt for credentials:i:0\nscreen mode id:i:1\ndesktopwidth:i:1600\ndesktopheight:i:1000\nsession bpp:i:32\naudiomode:i:0\n" | save -f $rdp

print $"wrote ($rdp) — host ($ip):3389, user Docker, password admin"
print "probing port 3389..."
if (port-open $ip 3389) {
    print "3389 reachable — opening"
} else {
    print "3389 not listening yet (Windows still installing?) — opening anyway"
}
os-open $rdp
