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

.PHONY: gitweb/set-owner
gitweb/set-owner: ##H @Local Set gitweb.owner for all repos (usage: make gitweb/set-owner OWNER="Shane")
ifndef OWNER
	$(error OWNER is undefined. Usage: make gitweb/set-owner OWNER="Shane")
endif
ifdef SUDO_USER
	@echo "Setting owner as $(SUDO_USER)..."
	@cp -f scripts/set_gitweb_owner.sh /tmp/set_gitweb_owner.sh
	@chmod +rx /tmp/set_gitweb_owner.sh
	su -P $(SUDO_USER) -c "cd /tmp && bash /tmp/set_gitweb_owner.sh '$(OWNER)'"
	@rm -f /tmp/set_gitweb_owner.sh
else
	@echo "Setting owner..."
	bash scripts/set_gitweb_owner.sh "$(OWNER)"
endif

.PHONY: gitweb/update-metadata
gitweb/update-metadata: ##H @Local Bulk update repo metadata from CSV (usage: make gitweb/update-metadata CSV=scripts/repo_metadata.csv)
	@echo "Updating repository metadata..."
ifdef SUDO_USER
	@# Copy script and CSV to /tmp so SUDO_USER can read them (bypassing restricted home dirs)
	@cp -f scripts/update_repo_metadata.py /tmp/update_repo_metadata.py
	@cp -f $(or $(CSV),scripts/repo_metadata.csv) /tmp/repo_metadata.csv
	@chmod +r /tmp/update_repo_metadata.py /tmp/repo_metadata.csv
	@echo "Running update script as $(SUDO_USER)..."
	su -P $(SUDO_USER) -c "cd /tmp && python3 /tmp/update_repo_metadata.py /tmp/repo_metadata.csv"
	@rm -f /tmp/update_repo_metadata.py /tmp/repo_metadata.csv
else
	python3 scripts/update_repo_metadata.py $(or $(CSV),scripts/repo_metadata.csv)
endif

.PHONY: git/init-remote
git/init-remote: ##H @Remote Initialize a new bare repository on VPS (usage: make git/init-remote REPO=projects/new-repo DESC="Description" [OWNER="Name"])
ifndef REPO
	$(error REPO is undefined. Usage: make git/init-remote REPO=projects/new-repo DESC="My Repo")
endif
ifndef DESC
	$(error DESC is undefined. usage: make git/init-remote REPO=... DESC="My Repo")
endif
	@# Auto-append .git if missing
	$(eval REPO_GIT := $(if $(filter %.git,$(REPO)),$(REPO),$(REPO).git))
	@echo "Initializing bare repository $(REPO_GIT) on $(VPS_HOST)..."
	ssh $(VPS) "mkdir -p /srv/git/$(REPO_GIT) && cd /srv/git/$(REPO_GIT) && git init --bare && touch git-daemon-export-ok"
	@echo "Marking directory as safe..."
	ssh $(VPS) "git config --global --add safe.directory /srv/git/$(REPO_GIT)"
ifdef OWNER
	@echo "Setting owner to $(OWNER)..."
	ssh $(VPS) "git config --file /srv/git/$(REPO_GIT)/config gitweb.owner '$(OWNER)'"
endif
	@echo "Setting description to $(DESC)..."
	ssh $(VPS) "echo '$(DESC)' > /srv/git/$(REPO_GIT)/description"
	@echo "Configuring local remote 'helio-web'..."
	-@git remote start helio-web ssh://$(VPS_USER)@$(VPS_HOST)/srv/git/$(REPO_GIT) 2>/dev/null || \
	  git remote add helio-web ssh://$(VPS_USER)@$(VPS_HOST)/srv/git/$(REPO_GIT)
	@echo "Repository initialized!"
	@echo "  Push: git push -u helio-web main"

.PHONY: git/rename-remote
git/rename-remote: ##H @Remote Rename/Move a repository on VPS (usage: make git/rename-remote OLD=projects/old.git NEW=@github.com/new.git)
ifndef OLD
	$(error OLD is undefined. Usage: make git/rename-remote OLD=projects/old.git NEW=projects/new.git)
endif
ifndef NEW
	$(error NEW is undefined. usage: make git/rename-remote OLD=... NEW=...)
endif
	@# Auto-append .git if missing
	$(eval OLD_GIT := $(if $(filter %.git,$(OLD)),$(OLD),$(OLD).git))
	$(eval NEW_GIT := $(if $(filter %.git,$(NEW)),$(NEW),$(NEW).git))
	[ "$(OLD_GIT)" = "$(NEW_GIT)" ] || ssh $(VPS) "mkdir -p /srv/git/$$(dirname $(NEW_GIT)) && mv /srv/git/$(OLD_GIT) /srv/git/$(NEW_GIT)" 
	@echo "Marking directory as safe..."
	ssh $(VPS) "git config --global --add safe.directory /srv/git/$(NEW_GIT)"
	@echo "Don't forget to update your local remote URL:"
	@echo "git remote set-url helio-web ssh://$(VPS_USER)@$(VPS_HOST)/srv/git/$(NEW_GIT)"
