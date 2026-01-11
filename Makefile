.SHELL := /bin/bash
# .ONESHELL:

ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@awk 'BEGIN {FS = ":.*?##H "}; \
			/##H/ && !/@awk.*?##H/ { \
					target=$$1; doc=$$2; \
					category="General"; \
					if (doc ~ /^@/) { \
							category=substr(doc, 2, index(doc, " ")-2); \
							doc=substr(doc, index(doc, " ")+1); \
					} \
					if (length(target) > max) max = length(target); \
					targets[NR] = target; docs[NR] = doc; cats[NR] = category; \
			} \
			END { \
					last_cat = ""; \
					for (i = 1; i <= NR; i++) { \
							if (cats[i] != "") { \
									if (cats[i] != last_cat) { \
											printf "\n\033[1;36m%s Commands:\033[0m\n", cats[i]; \
											last_cat = cats[i]; \
									} \
									printf "  \033[1;34m%-*s\033[0m  %s\n", max, targets[i], docs[i]; \
							} \
					} \
					print ""; \
			}' $(MAKEFILE_LIST)


VPS_HOST ?= dev.nutra.tk
VPS_USER ?= gg

VPS := $(VPS_USER)@$(VPS_HOST)

.PHONY: stage/nginx
stage/nginx: ##H @Remote Stage files on the remote VPS
	@echo "Staging files on $(VPS_HOST)..."
	ssh $(VPS) 'rm -rf ~/.nginx-staging && mkdir -p ~/.nginx-staging'
	scp -q -r etc/nginx/conf.d/*.conf $(VPS):~/.nginx-staging/
	scp -q scripts/deploy.sh $(VPS):~/.nginx-staging/

.PHONY: diff/nginx
diff/nginx: ##H @Remote Show diff between local and remote
	@echo "Checking diff against $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-staging/deploy.sh diff"

.PHONY: deploy/nginx
deploy/nginx: ##H @Remote Deploy staged files to remote
	@echo "Deploying checked-in nginx config to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-staging/deploy.sh"

.PHONY: test/nginx
test/nginx: ##H @Remote Test staged configuration without deploying
	@echo "Testing staged config on $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-staging/deploy.sh test"

.PHONY: certbot/nginx
certbot/nginx: ##H @Remote Run certbot on remote VPS
	@echo "Running certbot on $(VPS_HOST)..."
	ssh -t $(VPS) "sudo certbot --nginx"

# Direct Local Deployment (No Staging)
.PHONY: diff/local
diff/local: ##H @Local Show diff against system config
ifdef SUDO_USER
	@echo "Checking diff locally as $(SUDO_USER)..."
	su -P $(SUDO_USER) -c "bash scripts/deploy.sh diff"
else
	@echo "Checking diff locally..."
	bash scripts/deploy.sh diff
endif

.PHONY: test/local
test/local: ##H @Local Test current configuration
	@echo "Testing locally..."
	bash scripts/deploy.sh test

.PHONY: deploy/local
deploy/local: ##H Deploy Nginx and Gitweb configuration (local)
ifdef SUDO_USER
	@echo "Deploying locally as $(SUDO_USER)..."
	@# We need to run the entire script as the SUDO_USER to ensure they can sudo inside it
	su -P $(SUDO_USER) -c "bash scripts/deploy.sh"
else
	@echo "Deploying locally..."
	bash scripts/deploy.sh
endif

.PHONY: certbot/local
certbot/local: ##H @Local Run certbot locally (supports SUDO_USER)
ifdef SUDO_USER
	@echo "Running certbot locally as $(SUDO_USER)..."
	su -P $(SUDO_USER) -c "sudo certbot --nginx"
else
	@echo "Running certbot locally..."
	sudo certbot --nginx
endif

.PHONY: certbot/list-certs
certbot/list-certs: ##H @Local List managed certificates (supports SUDO_USER)
ifdef SUDO_USER
	@echo "Listing certificates as $(SUDO_USER)..."
	su -P $(SUDO_USER) -c "sudo certbot certificates"
else
	@echo "Listing certificates..."
	sudo certbot certificates
endif
