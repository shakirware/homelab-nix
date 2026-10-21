.PHONY: init plan apply router-init router-plan router-apply \
	deploy-storage deploy-media deploy-apps deploy-monitoring deploy-sensitive deploy-gw \
	deploy-ci deploy-all

init:
	tofu -chdir=infra/proxmox init

plan: init
	tofu -chdir=infra/proxmox plan

apply: init
	tofu -chdir=infra/proxmox apply

router-init:
	tofu -chdir=infra/router init

router-plan: router-init
	umask 077; tofu -chdir=infra/router plan -out=router.tfplan

router-apply:
	@test -f infra/router/router.tfplan || { echo "no saved plan: run make router-plan"; exit 1; }
	@if [ "$(ALLOW_DESTROY)" != 1 ] && tofu -chdir=infra/router show -no-color router.tfplan | grep -Eq '[1-9][0-9]* to destroy'; then \
		echo "plan destroys or replaces resources; review it, then ALLOW_DESTROY=1 make router-apply"; exit 1; fi
	tofu -chdir=infra/router apply router.tfplan
	@rm -f infra/router/router.tfplan

deploy-storage:
	nix run .#colmena -- apply --on vm-storage

deploy-media:
	nix run .#colmena -- apply --on vm-media

deploy-gw:
	nix run .#colmena -- apply --on vm-gw

deploy-sensitive:
	nix run .#colmena -- apply --on vm-sensitive

deploy-apps:
	nix run .#colmena -- apply --on vm-apps

deploy-monitoring:
	nix run .#colmena -- apply --on vm-monitoring

deploy-ci:
	nix run .#colmena -- apply --on vm-ci

deploy-all: deploy-storage deploy-media deploy-apps deploy-monitoring deploy-sensitive deploy-gw deploy-ci
