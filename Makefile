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

.PHONY: stage/nginx
stage/nginx: ##H @Remote Stage files on the remote VPS
	@echo "Staging files on $(VPS_HOST) (ENV=$(ENV))..."
	python3 scripts/gen_services_map.py etc/nginx/conf.d/default.$(ENV).conf
	# Tar files and stream to remote
	# Include only: "$(ENV)/*.conf" and non-env-specific "*.conf" files
	tar cz \
		etc/nginx/conf.d/*.conf \
		etc/nginx/conf.d/$(ENV)/*.conf \
		etc/gitweb.conf \
		scripts/gitweb-simplefrontend \
		scripts/deploy.sh \
		scripts/gen_services_map.py \
		scripts/homepage.html | \
		ssh $(VPS) "rm -rf ~/.nginx-ops/staging \
		            && mkdir -p ~/.nginx-ops/staging \
		            && tar xz -C ~/.nginx-ops/staging"


.PHONY: deploy/nginx
deploy/nginx: ##H @Remote Deploy staged files to remote
deploy/nginx: stage/nginx
	@echo "Connecting to $(VPS_HOST)..."
	@# We chain test && diff && deploy in ONE SSH session.
	@# This preserves the sudo timestamp so you only type your password once.
	ssh -t $(VPS) "bash ~/.nginx-ops/staging/scripts/deploy.sh test $(ENV) && \
	               bash ~/.nginx-ops/staging/scripts/deploy.sh $(ENV)"


.PHONY: deploy/klaus
deploy/klaus: ##H @Remote Deploy Klaus (systemd + nginx) and install deps
	@echo "Uploading deployment bundle..."
	tar cz -C etc/systemd/system klaus.service -C ../../nginx/conf.d klaus.conf -C ../../../scripts klaus_app.py | ssh $(VPS) "cat > /tmp/klaus-deploy.tgz"
	@echo "Installing on $(VPS_HOST)..."
	ssh -t $(VPS) "cd /tmp && tar xz -f klaus-deploy.tgz && \
		sudo bash -c '# apt-get update && apt-get install -y universal-ctags && \
		pip3 install klaus gunicorn markdown && \
		mv klaus_app.py /usr/local/bin/klaus_app.py && \
		mv klaus.service /etc/systemd/system/klaus.service && \
		systemctl daemon-reload && \
		systemctl enable --now klaus && \
		systemctl restart klaus && \
		mv /etc/nginx/conf.d/git-http.conf /etc/nginx/conf.d/git-http.conf.disabled 2>/dev/null || true && \
		mv klaus.conf /etc/nginx/conf.d/klaus.conf && \
		nginx -t && \
		systemctl reload nginx' && \
		rm klaus-deploy.tgz"
	@echo "Klaus deployed!"

.PHONY: certbot/nginx
certbot/nginx: ##H @Remote Run certbot on remote VPS
	@echo "Running certbot on $(VPS_HOST)..."
	ssh -t $(VPS) "sudo certbot --nginx"

# Direct Local Deployment (No Staging)
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
	git ls-files '*.py' | xargs black
	git ls-files '*.sh' | xargs shfmt -l -w
