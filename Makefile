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

.PHONY: deploy/klaus
deploy/klaus: ##H @Remote Deploy Klaus (systemd + nginx) and install deps
	@echo "Uploading deployment bundle..."
	tar cz -C etc/systemd/system klaus.service -C ../../nginx/conf.d klaus.conf | ssh $(VPS) "cat > /tmp/klaus-deploy.tgz"
	@echo "Installing on $(VPS_HOST)..."
	ssh -t $(VPS) "cd /tmp && tar xz -f klaus-deploy.tgz && \
		sudo pip3 install klaus gunicorn && \
		sudo mv klaus.service /etc/systemd/system/klaus.service && \
		sudo systemctl daemon-reload && \
		sudo systemctl enable --now klaus && \
		sudo mv /etc/nginx/conf.d/git-http.conf /etc/nginx/conf.d/git-http.conf.disabled 2>/dev/null || true && \
		sudo mv klaus.conf /etc/nginx/conf.d/klaus.conf && \
		sudo nginx -t && \
		sudo systemctl reload nginx && \
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
