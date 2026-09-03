NAMESPACE ?= test-netbird
CHART     ?= .
TIMEOUT   ?= 5m
RELEASE   ?= netbird
HELM      ?= helm

CONFIG_PATH ?= /etc/netbird/config.yaml

VALUES     ?= values_local.yml
VALUES_ARG := $(if $(wildcard $(VALUES)),--values $(VALUES),)

EXTRA ?=

COMMON = --namespace $(NAMESPACE) $(VALUES_ARG) $(EXTRA)

.DEFAULT_GOAL := help
.PHONY: help deps template template-debug install diff-upgrade upgrade force-upgrade uninstall wipe status test test-reload

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
	@echo '  test            smoke-test a deployed release from inside the cluster'
	@echo '  test-reload     prove a config change reaches the container (restarts the pod twice)'
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

test:
	@echo '== release =='
	@$(HELM) status $(RELEASE) --namespace $(NAMESPACE) | grep -E '^(STATUS|REVISION):'
	@echo '== rollout =='
	@kubectl --namespace $(NAMESPACE) rollout status deployment/$(RELEASE)-server --timeout=$(TIMEOUT)
	@kubectl --namespace $(NAMESPACE) rollout status deployment/$(RELEASE)-dashboard --timeout=$(TIMEOUT)
	@echo '== restarts (want 0; anything else means it has been crash-looping) =='
	@kubectl --namespace $(NAMESPACE) get pods \
		-o jsonpath='{range .items[*]}  {.metadata.name}{"  restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
	@echo '== config as the server container reads it =='
	@kubectl --namespace $(NAMESPACE) exec deployment/$(RELEASE)-server -- \
		grep -cE 'encryptionKey|authSecret|issuer' $(CONFIG_PATH) >/dev/null \
		&& echo '  config.yaml mounted, with the required fields'
	@echo '== endpoints =='
	@kubectl --namespace $(NAMESPACE) run smoke-$$$$ --rm -i --restart=Never --quiet \
		--image=busybox:1.36 --command -- sh -c '\
		wget -qO- -T5 http://$(RELEASE)-dashboard/ >/dev/null \
		  || { echo "  dashboard  /            FAILED"; exit 1; }; \
		echo "  dashboard  /            200"; \
		wget -SqO- -T5 http://$(RELEASE)-server-http/api/users 2>&1 | grep -q 401 \
		  || { echo "  server     /api/users   FAILED (expected 401)"; exit 1; }; \
		echo "  server     /api/users   401 (up, rejecting unauthenticated)"; \
		wget -qO- -T5 http://$(RELEASE)-server-http:9090/metrics | grep -q . \
		  || { echo "  server     /metrics     FAILED"; exit 1; }; \
		echo "  server     /metrics     serving"'

test-reload:
	@echo 'Restarts the server pod twice: once for the probe change, once reverting it.'
	@set -e; \
	probe=$$(( ($$(date +%s) % 1000) + 1000 )); \
	sum() { kubectl --namespace $(NAMESPACE) get deploy $(RELEASE)-server \
		-o jsonpath='{.spec.template.metadata.annotations.checksum/config}'; }; \
	pod() { kubectl --namespace $(NAMESPACE) get pod -l netbird-app=$(RELEASE)-server \
		-o jsonpath='{.items[0].metadata.name}'; }; \
	revert() { $(HELM) upgrade --install $(RELEASE) $(CHART) $(COMMON) --create-namespace \
		--wait --timeout $(TIMEOUT) >/dev/null 2>&1 || true; }; \
	b_pod=$$(pod); b_sum=$$(sum); \
	echo "  before   pod=$$b_pod  checksum=$$(echo $$b_sum | cut -c1-12)"; \
	trap 'revert' EXIT; \
	$(HELM) upgrade --install $(RELEASE) $(CHART) $(COMMON) --create-namespace \
		--wait --timeout $(TIMEOUT) \
		--set global.server.reverseProxy.accessLogRetentionDays=$$probe >/dev/null; \
	a_pod=$$(pod); a_sum=$$(sum); \
	echo "  after    pod=$$a_pod  checksum=$$(echo $$a_sum | cut -c1-12)"; \
	[ "$$b_sum" != "$$a_sum" ] || { echo '  FAILED: checksum did not change'; exit 1; }; \
	[ "$$b_pod" != "$$a_pod" ] || { echo '  FAILED: pod did not roll'; exit 1; }; \
	kubectl --namespace $(NAMESPACE) exec deployment/$(RELEASE)-server -- \
		grep -q "accessLogRetentionDays: $$probe" $(CONFIG_PATH) \
		|| { echo '  FAILED: container is still reading the old config'; exit 1; }; \
	echo "  container reads accessLogRetentionDays: $$probe"; \
	revert; trap - EXIT; \
	[ "$$(sum)" = "$$b_sum" ] || { echo '  FAILED: revert did not restore the original config'; exit 1; }; \
	echo '  reverted; checksum back to its original value'

status:
	kubectl --namespace $(NAMESPACE) get pods,svc,pvc
	@echo ''
	@for k in httproute grpcroute udproute; do \
		kubectl --namespace $(NAMESPACE) get $$k 2>/dev/null || true; \
	done
