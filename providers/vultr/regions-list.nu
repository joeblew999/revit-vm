# List all Vultr regions. Use the ID column to set VULTR_REGION in
# mise.local.toml — common picks: fra (Frankfurt), ams (Amsterdam),
# ewr (NJ — closest to North America East).

^fnox exec --if-missing ignore -- vultr-cli regions list
