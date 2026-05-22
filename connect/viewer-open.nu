# Open dockur's web viewer (port 8006) in the default browser. Shows
# Windows install progress, then Windows itself.

let ip = (mise run vm:ip | str trim)
print $"opening http://($ip):8006/"
^open $"http://($ip):8006/"
