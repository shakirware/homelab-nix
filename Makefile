.PHONY: init plan apply \
	deploy-storage deploy-media deploy-apps deploy-monitoring deploy-sensitive deploy-gw \
	deploy-all

init:
	tofu -chdir=infra init

plan: init
	tofu -chdir=infra plan

apply: init
	tofu -chdir=infra apply

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

deploy-all: deploy-storage deploy-media deploy-apps deploy-monitoring deploy-sensitive deploy-gw
