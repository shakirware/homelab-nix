# One-time bootstrap so OpenTofu can manage the router (run once, by hand).
# Contains no secrets. See docs/network.md for the full procedure.
#
# 1. A router-local CA and an HTTPS certificate for the REST API. The CA's
#    public certificate is committed as infra/router/router-ca.crt so the
#    provider verifies TLS instead of skipping it.
/certificate add name=router-ca common-name=router-ca key-size=prime256v1 \
    key-usage=key-cert-sign,crl-sign days-valid=3650
/certificate sign router-ca
/certificate add name=router-https common-name=192.168.1.1 subject-alt-name=IP:192.168.1.1 \
    key-size=prime256v1 key-usage=digital-signature,key-agreement,tls-server days-valid=825
/certificate sign router-https ca=router-ca
/certificate export-certificate router-ca file-name=router-ca

# 2. REST API over HTTPS, reachable only from the admin workstation.
/ip service set www-ssl certificate=router-https address=192.168.1.74/32 tls-version=only-1.2 disabled=no

# 3. A least-privilege group for OpenTofu: REST API with read/write and no
#    interactive login rights. "policy" dates from when OpenTofu managed
#    users; accounts are now operator-owned (users.rsc).
/user group add name=iac comment="OpenTofu (infra/router)" \
    policy=read,write,policy,test,api,rest-api,!local,!telnet,!ssh,!ftp,!reboot,!winbox,!password,!web,!sniff,!sensitive,!romon

# 4. Run by the operator, never stored in Git. The same value goes into
#    secrets/env.yaml as TF_VAR_routeros_password:
#      /user add name=tofu group=iac address=192.168.1.74/32 comment="OpenTofu (infra/router)" password=<generated>
