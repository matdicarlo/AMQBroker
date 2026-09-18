# 1. Fix ownership
sudo chown -R ldap:ldap /etc/openldap/slapd.d/
sudo chown -R ldap:ldap /var/lib/ldap/

# 2. Relax SELinux for the test
sudo setenforce 0

# 3. Start slapd
sudo systemctl start slapd

