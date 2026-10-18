# Router accounts, run by the operator in this order. No password
# is stored here or in OpenTofu: RouterOS needs one to create a user, and a
# netwatch dead-man cannot change accounts, so each step is verified before
# the next and the factory account goes last.
#
# 1. Create the named administrator. Generate the password in your password
#    manager on a device other than the laptop: it is also the emergency
#    MAC-WinBox login if the laptop fails.
#      /user add name=shakir group=full comment="Administrator" password=<from password manager>
#
#    No address restriction on the account: the IP services and firewall
#    already confine IP logins to the admin workstation, and MAC-WinBox from a
#    replacement computer must still work.
#
# 2. Add the laptop's SSH key (nix/modules/users: shakir@homelab-laptop):
/user ssh-keys add user=shakir key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFI5k1s3bXew4ud5tt9uI01/zZrTHilqSrayU8C9J0IQ shakir@homelab-laptop"
#
# 3. Verify both paths before going further:
#      ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519_homelab shakir@192.168.1.1 ':put ok'
#      WinBox (IP, then MAC) as shakir with the new password
#    Then set "User shakir" for Host router in ~/.ssh/config.
#
# 4. Only then retire the factory account:
#      /user set admin disabled=yes
#
# Undo: /user set admin disabled=no (as shakir), or log in as admin and
# /user remove shakir.
