.SHELL := /bin/bash
# .ONESHELL:

-include .env

VPS_HOST ?= dev.nutra.tk
VPS_USER ?= gg
VPS = $(VPS_USER)@$(VPS_HOST)

.PHONY: stage/nginx
stage/nginx:
	@echo "Staging files on $(VPS_HOST)..."
	tar --transform 's|.*/||' -czf - etc/nginx/conf.d/*.conf scripts/deploy.sh | \
		ssh $(VPS) "rm -rf ~/nginx-staging && mkdir -p ~/nginx-staging && tar -xzv -C ~/nginx-staging"

.PHONY: diff/nginx
diff/nginx:
	@echo "Checking diff against $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/nginx-staging/deploy.sh diff"

.PHONY: deploy/nginx
deploy/nginx:
	@echo "Deploying checked-in nginx config to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/nginx-staging/deploy.sh"
