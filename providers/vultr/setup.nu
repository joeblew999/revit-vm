# Vultr first-time setup helper. Prints the four IDs you need to fill in
# at mise.local.toml: VULTR_REGION, VULTR_PLAN, VULTR_SSH_KEY_ID, VULTR_OS_ID.
# Shows current selections alongside the enumeration so you can see what's
# missing.

print "──── Vultr setup wizard ────"
print ""
print "Current selections from mise.toml + mise.local.toml:"
print $"  VULTR_REGION      = '($env.VULTR_REGION)'"
print $"  VULTR_PLAN        = '($env.VULTR_PLAN)'"
print $"  VULTR_OS_ID       = '($env.VULTR_OS_ID)'"
print $"  VULTR_SSH_KEY_ID  = '($env.VULTR_SSH_KEY_ID)'"
print $"  VULTR_LABEL       = '($env.VULTR_LABEL)'"
print ""

let token_probe = (^fnox get VULTR_API_KEY | complete)
if $token_probe.exit_code != 0 {
    print "❌ VULTR_API_KEY not in keychain — run `mise run vultr:token:set` first."
    print "   Generate at https://my.vultr.com → Account → API."
    exit 1
}
print "✅ VULTR_API_KEY present in keychain."
print ""

print "──── Regions ────"
print "(pick one; common: fra=Frankfurt, ams=Amsterdam, ewr=NJ)"
^fnox exec --if-missing ignore -- vultr-cli regions list
print ""

print "──── Bare Metal plans (≥6c only — what dockur needs) ────"
nu providers/vultr/enumerate-plans.nu
print ""

print "──── SSH keys uploaded to your Vultr account ────"
print "(if empty, upload one first: vultr-cli ssh-key create --name … --key 'ssh-ed25519 …')"
^fnox exec --if-missing ignore -- vultr-cli ssh-key list
print ""

print "──── Ubuntu OS IDs ────"
print "(default 1743 = Ubuntu 24.04 x64 — usually no need to change)"
nu providers/vultr/enumerate-os.nu
print ""

print "──── Next ────"
print "Open mise.local.toml and set:"
print "  [env]"
print "  VM_PROVIDER = \"vultr\""
print "  VULTR_REGION = \"<region-id-from-above>\""
print "  VULTR_PLAN = \"<plan-id-from-above>\""
print "  VULTR_SSH_KEY_ID = \"<ssh-uuid-from-above>\""
print ""
print "Then: `mise run deps:check` to verify, then `mise run start`."
