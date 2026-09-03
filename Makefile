NAMESPACE ?= test-netbird
CHART     ?= .
TIMEOUT   ?= 5m
RELEASE   ?= netbird
HELM      ?= helm

VALUES     ?= values_local.yml
VALUES_ARG := $(if $(wildcard $(VALUES)),--values $(VALUES),)

EXTRA ?=

COMMON = --namespace $(NAMESPACE) $(VALUES_ARG) $(EXTRA)

.DEFAULT_GOAL := help
.PHONY: help deps template template-debug install diff-upgrade upgrade force-upgrade uninstall wipe status

help:
	@echo 'Targets:'
	@echo '  deps            helm dependency update + build'
	@echo '  template        render manifests to stdout'
	@echo '  template-debug  render with --debug: prints computed values, and renders even on error'
	@echo '  install         first install, creating the namespace'
	@echo '  diff-upgrade    show what an upgrade would change (needs the helm-diff plugin)'
	@echo '  upgrade         upgrade --install, waits for readiness'
	@echo '  force-upgrade   upgrade --force: deletes and recreates what it cannot patch'
	@echo '  uninstall       remove the release (the PVC is deliberately kept)'
	@echo '  wipe            delete the whole namespace, PVC and data included'
	@echo '  status          pods, services and routes for the release'
	@echo ''
	@echo 'Current values:'
	@echo '  NAMESPACE=$(NAMESPACE)  RELEASE=$(RELEASE)  CHART=$(CHART)  TIMEOUT=$(TIMEOUT)'
	@echo '  VALUES=$(VALUES) $(if $(wildcard $(VALUES)),(found),(absent -- cp values_example.yml values_local.yml))'

deps:
	$(HELM) dependency update $(CHART)
	$(HELM) dependency build $(CHART)

template:
	@$(HELM) template $(RELEASE) $(CHART) $(COMMON)

template-debug:
	@$(HELM) template $(RELEASE) $(CHART) $(COMMON) --debug

install:
	$(HELM) install $(RELEASE) $(CHART) $(COMMON) \
		--create-namespace --wait --timeout $(TIMEOUT)

diff-upgrade:
	@$(HELM) plugin list | grep -q '^diff' \
		|| { echo 'helm-diff is not installed:'; \
		     echo '  helm plugin install https://github.com/databus23/helm-diff'; exit 1; }
	$(HELM) diff upgrade $(RELEASE) $(CHART) $(COMMON)

upgrade:
	$(HELM) upgrade --install $(RELEASE) $(CHART) $(COMMON) \
		--create-namespace \
		--wait --timeout $(TIMEOUT)

force-upgrade:
	$(HELM) upgrade --install $(RELEASE) $(CHART) $(COMMON) \
		--create-namespace \
		--force --wait --timeout $(TIMEOUT)

uninstall:
	$(HELM) uninstall $(RELEASE) --namespace $(NAMESPACE) --wait --timeout $(TIMEOUT)

wipe:
	@echo 'Deleting namespace "$(NAMESPACE)" and everything in it, PVC included.'
	@[ "$(CONFIRM)" = 'yes' ] || { \
		printf 'Type the namespace to confirm: '; \
		read ans; [ "$$ans" = '$(NAMESPACE)' ] || { echo 'aborted'; exit 1; }; }
	-$(HELM) uninstall $(RELEASE) --namespace $(NAMESPACE) --wait --timeout $(TIMEOUT)
	kubectl delete namespace $(NAMESPACE) --wait --timeout=$(TIMEOUT)

status:
	kubectl --namespace $(NAMESPACE) get pods,svc,pvc
	@echo ''
	@for k in httproute grpcroute udproute; do \
		kubectl --namespace $(NAMESPACE) get $$k 2>/dev/null || true; \
	done
