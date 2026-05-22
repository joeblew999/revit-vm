# List SSH keys uploaded to your Vultr account. Use the ID column (a UUID)
# to set VULTR_SSH_KEY_ID in mise.local.toml. The key's public side must
# match the local SSH_KEY_FILE in mise.toml.

^fnox exec --if-missing ignore -- vultr-cli ssh-key list
