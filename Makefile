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

.PHONY: check-vars
check-vars: ##H @General Check active configuration variables (Auto-detected)
	@printf "\033[1;36m--- Makefile Variables ---\033[0m\n"
	@printf "\033[1;34m%-25s\033[0m : %s\n" "ENV" "$(ENV)"
	@printf "\033[1;34m%-25s\033[0m : %s\n" "VPS" "$(VPS)"
	@printf "\n\033[1;36m--- etc/nutra.env Variables ---\033[0m\n"
	@if [ -f etc/nutra.env ]; then \
		set -a && source etc/nutra.env 2>/dev/null && set +a; \
		vars=$$(sed -n 's/^\s*\([A-Z0-9_]\+\)=.*/\1/p' etc/nutra.env | sort | uniq); \
		for var in $$vars; do \
			val="$${!var}"; \
			if [[ "$$var" =~ (PASSWORD|TOKEN|KEY|SECRET|DESC) ]]; then \
				val="******"; \
			fi; \
			printf "\033[1;32m%-25s\033[0m : %s\n" "$$var" "$$val"; \
		done \
	else \
		echo "etc/nutra.env not found."; \
	fi


VPS_HOST ?= dev.nutra.tk
VPS_USER ?= gg

VPS := $(VPS_USER)@$(VPS_HOST)

# Logic:
# 1. Default ENV to dev.
# 2. Allow user to override ENV=prod.
# 3. Set VPS_HOST based on ENV.

ENV ?= dev

ifeq ($(ENV),prod)
	VPS_HOST := $(VPS_HOST_PROD)
else
	VPS_HOST := $(VPS_HOST_DEV)
endif

VPS := $(VPS_USER)@$(VPS_HOST)
BACKUP_DIR := $(HOME)/.backups/rocksdb_backups

.PHONY: stage/vps
stage/vps: ##H @Remote Stage all configuration files on the remote VPS
	@echo "Staging files on $(VPS_HOST) (ENV=$(ENV))..."
	ENV=$(ENV) python3 scripts/gen_services_map.py
	# Tar files and stream to remote
	tar cz \
		etc/nginx/conf.d/*.conf \
		etc/nutra.env \
		etc/nginx/conf.d/$(ENV)/*.conf \
		etc/systemd/system/*.service \
		etc/fail2ban \
		etc/conduwuit/*.toml \
		etc/matrix-conduit/*.toml \
		etc/matrix-synapse/**/*.yaml \
		etc/gitweb.conf \
		opt/stalwart/etc/*.toml \
		scripts/gitweb-simplefrontend \
		scripts/deploy.sh \
		scripts/gen_services_map.py \
		scripts/collect_stats.sh \
		etc/systemd/system/*.timer \
		opt/api/api.py \
		scripts/homepage.html | \
		ssh $(VPS) "rm -rf ~/.nginx-ops/staging \
		            && mkdir -p ~/.nginx-ops/staging \
		            && tar xz -C ~/.nginx-ops/staging"

.PHONY: stage/nginx
stage/nginx: stage/vps


.PHONY: deploy/vps
deploy/vps: ##H @Remote Deploy staged files to remote VPS
deploy/vps: stage/vps
	@echo "Logging deployment..."
	@echo "$(shell date '+%Y-%m-%d %H:%M:%S') [$(ENV)] User: $(USER) \
		Commit: $(shell git describe --always --dirty) - $(shell git log -1 --format='%s')" >> deployment.log
	@echo "Connecting to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-ops/staging/scripts/deploy.sh test $(ENV) && \
	               bash ~/.nginx-ops/staging/scripts/deploy.sh $(ENV)"

.PHONY: deploy/nginx
deploy/nginx: ##H @Remote Deploy Nginx configuration only
deploy/nginx: stage/nginx
	@echo "Logging deployment..."
	@echo "$(shell date '+%Y-%m-%d %H:%M:%S') [$(ENV)] User: $(USER) (Nginx Only) \
		Commit: $(shell git describe --always --dirty) - $(shell git log -1 --format='%s')" >> deployment.log
	echo "Connecting to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-ops/staging/scripts/deploy.sh test $(ENV) && \
	               bash ~/.nginx-ops/staging/scripts/deploy.sh $(ENV) --nginx-only"

.PHONY: deploy/fail2ban
deploy/fail2ban: ##H @Remote Deploy Fail2Ban configuration only
deploy/fail2ban: stage/nginx
	@echo "Logging deployment..."
	@echo "$(shell date '+%Y-%m-%d %H:%M:%S') [$(ENV)] User: $(USER) (Fail2Ban Only) \
		Commit: $(shell git describe --always --dirty) - $(shell git log -1 --format='%s')" >> deployment.log
	@echo "Connecting to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-ops/staging/scripts/deploy.sh $(ENV) --fail2ban-only"

.PHONY: certbot/nginx
certbot/nginx: ##H @Remote Run certbot on remote VPS
	@echo "Running certbot on $(VPS_HOST)..."
	ssh -t $(VPS) "sudo certbot --nginx"

# Application Deployment
.PHONY: build/website
build/website: ##H @Local Build the static website
	$(MAKE) -C opt/my-website build

.PHONY: deploy/website
deploy/website: ##H @Remote Deploy the static website
	$(MAKE) -C opt/my-website deploy VPS="$(VPS)"

# Direct Local Deployment (No Staging)
.PHONY: run/api
run/api: ##H @Local Run the API server locally with dev bypass
	@echo "Starting API on port 5000..."
	@set -a && source etc/nutra.env && set +a && \
	 export CAPTCHA_BYPASS_TOKEN="dev_token" && \
	 export RESUME_PATH="$(PWD)/opt/api/assets/dummy_resume.pdf" && \
	 python3 opt/api/api.py

.PHONY: diff/local
diff/local: ##H @Local Show diff against system config
ifdef SUDO_USER
	@echo "Checking diff locally as $(SUDO_USER)..."
	su -P $(SUDO_USER) -c "bash scripts/deploy.sh diff $(ENV)"
else
	@echo "Checking diff locally..."
	bash scripts/deploy.sh diff $(ENV)
endif

.PHONY: test/local
test/local: ##H @Local Test current configuration
	@echo "Testing locally..."
	bash scripts/deploy.sh test $(ENV)

.PHONY: deploy/local
deploy/local: ##H Deploy Nginx and Gitweb configuration (local)
ifdef SUDO_USER
	@echo "Deploying locally as $(SUDO_USER)..."
	@# We need to run the entire script as the SUDO_USER to ensure they can sudo inside it
	su -P $(SUDO_USER) -c "bash scripts/deploy.sh $(ENV)"
else
	@echo "Deploying locally..."
	@echo "$(shell date '+%Y-%m-%d %H:%M:%S') [$(ENV)] User: $(USER) \
		Commit: $(shell git describe --always --dirty) - $(shell git log -1 --format='%s')" >> deployment.log
	bash scripts/deploy.sh $(ENV)
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

# ----------------- Safe Migration -----------------

.PHONY: backup/conduwuit
backup/conduwuit: ##H @Remote Safe Backup: Stop -> Stream to $(BACKUP_DIR) -> Start
	@echo "\033[1;33m[!] WARNING: This will temporarily STOP Matrix services to backup the DB.\033[0m"
	@read -p "Are you sure? [y/N] " ans && [ $${ans:-N} = y ]
	@mkdir -p $(BACKUP_DIR)
	@echo "1. Stopping services on $(VPS_HOST)..."
	@ssh -t $(VPS) "sudo systemctl stop continuwuity conduwuit || true"
	@echo "2. Streaming backup to $(BACKUP_DIR)/conduwuit_$$(date +%s).tar.gz ..."
	@ssh $(VPS) "sudo tar cz -C /var/lib continuwuity" > $(BACKUP_DIR)/conduwuit_$$(date +%s).tar.gz
	@echo "   Backup complete."
	@echo "3. Restarting services..."
	@ssh -t $(VPS) "sudo systemctl start continuwuity || sudo systemctl start conduwuit || true"
	@echo "\033[1;32mBackup Complete!\033[0m"

.PHONY: run/conduwuit-local
run/conduwuit-local: ##H @Local Run Conduwuit locally using latest backup
	@echo "Finding latest backup in $(BACKUP_DIR)..."
	$(eval LATEST_BACKUP := $(shell ls -t $(BACKUP_DIR)/conduwuit_*.tar.gz | head -1))
	@if [ -z "$(LATEST_BACKUP)" ]; then echo "No backup found!"; exit 1; fi
	@echo "Using: $(LATEST_BACKUP)"
	@mkdir -p /tmp/conduwuit-test-db
	@rm -rf /tmp/conduwuit-test-db/*
	@echo "Extracting to /tmp/conduwuit-test-db..."
	@tar xf "$(LATEST_BACKUP)" -C /tmp/conduwuit-test-db
	@echo "Generate temp config..."
	@cp etc/conduwuit/conduwuit.toml /tmp/conduwuit-local.toml
	@sed -i 's|database_path = .*|database_path = "/tmp/conduwuit-test-db/continuwuity/"|' /tmp/conduwuit-local.toml
	@sed -i 's|server_name = .*|server_name = "localhost"|' /tmp/conduwuit-local.toml
	@echo "Starting continuwuity..."
	@continuwuity --config /tmp/conduwuit-local.toml

.PHONY: migrate/conduwuit
migrate/conduwuit: ##H @Remote Safe Migration: Stop -> Backup -> Deploy -> Start
	@echo "\033[1;33m[!] WARNING: This will stop Matrix services, backup DB locally, and deploy.\033[0m"
	@read -p "Are you sure? [y/N] " ans && [ $${ans:-N} = y ]
	@mkdir -p $(BACKUP_DIR)
	@echo "1. Stopping services on $(VPS_HOST)..."
	@ssh -t $(VPS) "sudo systemctl stop continuwuity conduwuit || true"
	@echo "2. Streaming backup to $(BACKUP_DIR)/conduwuit_$$(date +%s).tar.gz ..."
	@ssh $(VPS) "sudo tar cz -C /var/lib continuwuity" > $(BACKUP_DIR)/conduwuit_$$(date +%s).tar.gz
	@echo "   Backup complete."
	@echo "3. Deploying new configuration..."
	@$(MAKE) deploy/vps ENV=$(ENV)
	@echo "4. Starting new service and disabling old..."
	@ssh -t $(VPS) "sudo systemctl start conduwuit && sudo systemctl disable continuwuity --now || true"
	@echo "\033[1;32mMigration Complete!\033[0m"

# ----------------- Git Repo Management -----------------

.PHONY: git/init
git/init: ##H @Remote Initialize new bare repo (usage: make git/init NAME=projects/new [DESC="..."])
	@python3 scripts/manage_repos.py --remote $(VPS) init $(if $(NAME),--name "$(NAME)") $(if $(DESC),--desc "$(DESC)") $(if $(OWNER),--owner "$(OWNER)") --auto-remote

.PHONY: git/add
git/add: ##H @Remote Clone a repository (usage: make git/add URL=... [NAME=...] [DESC=...])
ifndef URL
	$(error URL is undefined. Usage: make git/add URL=https://github.com/foo/bar.git)
endif
	@python3 scripts/manage_repos.py --remote $(VPS) add $(URL) $(if $(NAME),--name "$(NAME)") $(if $(DESC),--desc "$(DESC)") $(if $(OWNER),--owner "$(OWNER)")

.PHONY: git/rename
git/rename: ##H @Remote Rename a repository (usage: make git/rename OLD=... NEW=...)
ifndef OLD
	$(error OLD is undefined. Usage: make git/rename OLD=projects/old NEW=projects/new)
endif
ifndef NEW
	$(error NEW is undefined.)
endif
	@python3 scripts/manage_repos.py --remote $(VPS) rename $(OLD) $(NEW)

.PHONY: git/update
git/update: ##H @Remote Update repo metadata (usage: make git/update NAME=... [DESC=...] [OWNER=...])
ifndef NAME
	$(error NAME is undefined. usage: make git/update NAME=projects/foo ...)
endif
	@python3 scripts/manage_repos.py --remote $(VPS) update $(NAME) $(if $(DESC),--desc "$(DESC)") $(if $(OWNER),--owner "$(OWNER)")

.PHONY: git/list
git/list: ##H @Local List tracked repositories
	@python3 scripts/manage_repos.py list

.PHONY: git/sync
git/sync: ##H @Local Sync remote repositories to local JSON
	@python3 scripts/manage_repos.py --remote $(VPS) sync

.PHONY: format
format: ##H @Local Format python and shell scripts
	git ls-files '*.conf' | xargs nginxfmt
	git ls-files '*.py' | xargs black
	git ls-files '*.sh' | xargs shfmt -l -w
	cd opt/my-website && make format
