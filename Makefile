HOSTS := $(patsubst nix/hosts/vm-%/,%,$(sort $(wildcard nix/hosts/vm-*/)))
DEPLOY_TARGETS := $(addprefix deploy-,$(HOSTS))

.PHONY: init plan apply router-init router-plan router-apply $(DEPLOY_TARGETS) deploy-all

init:
	tofu -chdir=infra/proxmox init

plan: init
	tofu -chdir=infra/proxmox plan

apply: init
	tofu -chdir=infra/proxmox apply
	infra/proxmox/backup-state.sh
	infra/proxmox/backup-host.sh

router-init:
	tofu -chdir=infra/router init

router-plan: router-init
	umask 077; tofu -chdir=infra/router plan -out=router.tfplan

router-apply:
	@test -f infra/router/router.tfplan || { echo "no saved plan: run make router-plan"; exit 1; }
	@if [ "$(ALLOW_DESTROY)" != 1 ] && tofu -chdir=infra/router show -no-color router.tfplan | grep -Eq '[1-9][0-9]* to destroy'; then \
		echo "plan destroys or replaces resources; review it, then ALLOW_DESTROY=1 make router-apply"; exit 1; fi
	tofu -chdir=infra/router apply router.tfplan
	infra/router/backup-state.sh
	infra/router/backup-config.sh
	@rm -f infra/router/router.tfplan

$(DEPLOY_TARGETS): deploy-%:
	nix run .#colmena -- apply --on vm-$*

deploy-all: deploy-storage $(filter-out deploy-storage,$(DEPLOY_TARGETS))
