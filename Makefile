.SHELL := /bin/bash
# .ONESHELL:

-include .env

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
VPS = $(VPS_USER)@$(VPS_HOST)

.PHONY: stage/nginx
stage/nginx:	##H @Deploy Stage files for deployment
	@echo "Staging files on $(VPS_HOST)..."
	tar --transform 's|.*/||' --exclude='secrets.conf' -czf - etc/nginx/conf.d/*.conf scripts/deploy.sh | \
		ssh $(VPS) "rm -rf ~/.nginx-staging && mkdir -p ~/.nginx-staging && tar -xzv -C ~/.nginx-staging"

.PHONY: diff/nginx
diff/nginx:	##H @Deploy See diff, test with nginx -t
	@echo "Checking diff against $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-staging/deploy.sh diff"

.PHONY: deploy/nginx
deploy/nginx:	##H @Deploy Copy into place and reload nginx
	@echo "Deploying checked-in nginx config to $(VPS_HOST)..."
	ssh -t $(VPS) "bash ~/.nginx-staging/deploy.sh"
