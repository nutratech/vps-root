.SHELL := /bin/bash
# .ONESHELL:

VPS_HOST ?= dev.nutra.tk
VPS_USER ?= gg

.PHONY: stage/nginx
stage/nginx:
	@echo "Staging files on $(VPS_HOST)..."
	ssh $(VPS_USER)@$(VPS_HOST) 'rm -rf ~/nginx-staging && mkdir -p ~/nginx-staging'
	scp -q -r etc/nginx/conf.d/*.conf $(VPS_USER)@$(VPS_HOST):~/nginx-staging/
	scp -q scripts/deploy.sh $(VPS_USER)@$(VPS_HOST):~/nginx-staging/

.PHONY: diff/nginx
diff/nginx:
	@echo "Checking diff against $(VPS_HOST)..."
	ssh -t $(VPS_USER)@$(VPS_HOST) "bash ~/nginx-staging/deploy.sh diff"

.PHONY: deploy/nginx
deploy/nginx:
	@echo "Deploying checked-in nginx config to $(VPS_HOST)..."
	ssh -t $(VPS_USER)@$(VPS_HOST) "bash ~/nginx-staging/deploy.sh"
