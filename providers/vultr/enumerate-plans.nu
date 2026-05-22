# List Vultr Bare Metal plans. Filter to those with ≥6 cores (dockur runs
# Windows with CPU_CORES=6 in cloud-init-kvm.yaml). Use the ID column to
# set VULTR_PLAN in mise.local.toml.

let raw = (^fnox exec --if-missing ignore -- vultr-cli plans metal -o json | from json)
# Try common JSON shapes; fall back to dumping raw.
let plans = ($raw.plans? | default null)

if $plans == null {
    print "(could not parse plans JSON — falling back to raw output)"
    ^fnox exec --if-missing ignore -- vultr-cli plans metal
    exit 0
}

print "Bare Metal plans with ≥6 cores (dockur needs CPU_CORES=6):"
$plans | where ($it.cpu_count? | default 0) >= 6 | sort-by monthly_cost | each {|p|
    let mc = ($p.monthly_cost? | default "?")
    let hc = ($p.hourly_cost? | default "?")
    let id = ($p.id? | default ($p.bare_metal_plan_id? | default "?"))
    let cores = ($p.cpu_count? | default "?")
    let ram = ($p.ram? | default "?")
    let disk = ($p.disk? | default "?")
    print $"  ($id)  ($cores)c  RAM ($ram)MB  disk ($disk)GB  $($mc)/mo  $($hc)/hr"
} | ignore
