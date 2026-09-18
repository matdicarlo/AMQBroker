# 1. Stop the service
sudo systemctl stop slapd

# 2. Wipe the config and data directories
sudo rm -rf /etc/openldap/slapd.d/*
sudo rm -rf /var/lib/ldap/*

# 3. Create a workspace for our scratch files
mkdir ldap-scratch
mkdir ldap-scratch/certs
cd ldap-scratch

