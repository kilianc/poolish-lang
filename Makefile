PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BINARY_NAME := poolish

# - binary dependencies
GOTESTSUM_VERSION := v1.11.0
GOFUMPT_VERSION := v0.6.0
GOLANGCI_LINT_VERSION := v1.57.2
ENTR_VERSION := 5.5

# - multi-platform build
OS_LIST := darwin linux
ARCH_LIST := arm64 amd64
BUILD_TARGETS := $(foreach os,$(OS_LIST),$(foreach arch,$(ARCH_LIST),bin/$(BINARY_NAME)-$(os)-$(arch)))
RELEASE_TARGETS := $(foreach os,$(OS_LIST),$(foreach arch,$(ARCH_LIST),bin/$(BINARY_NAME)-$(os)-$(arch).tar.gz))

# - remote testing

REMOTE_HOSTS := $(shell cat hosts.txt 2> /dev/null || echo "")

# - default target

.DEFAULT_GOAL := run

# - install binary dependencies

bin/entr:
# https://eradman.com/entrproject/entr.1.html
	@curl -o bin/entr-$(ENTR_VERSION).tar.gz https://eradman.com/entrproject/code/entr-$(ENTR_VERSION).tar.gz
	@tar -xf bin/entr-$(ENTR_VERSION).tar.gz -C bin
	@cd bin/entr-$(ENTR_VERSION) && ./configure && make
	@mv bin/entr-$(ENTR_VERSION)/entr bin/entr
	@rm -rf bin/entr-$(ENTR_VERSION)*

bin/git-chglog:
	@mkdir -p $(@D)
	@GOBIN=$(PROJECT_DIR)/$(@D) go install github.com/git-chglog/git-chglog/cmd/git-chglog@latest

bin/golangci-lint:
	@mkdir -p $(@D)
	@GOBIN=$(PROJECT_DIR)/$(@D) go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

bin/gofumpt:
	@mkdir -p $(@D)
	@GOBIN=$(PROJECT_DIR)/$(@D) go install mvdan.cc/gofumpt@$(GOFUMPT_VERSION)

bin/gotestsum:
	@mkdir -p $(@D)
	@GOBIN=$(PROJECT_DIR)/$(@D) go install gotest.tools/gotestsum@$(GOTESTSUM_VERSION)

# - run, test, lint, format etc.

.env:
	@echo "" > .env

.PHONY: run
run: .env
	@source .env && go run cmd/$(BINARY_NAME)/main.go

.PHONY: run-watch
run-watch: bin/entr
	$(eval flags := rd)
	@trap '_run_=false' SIGINT; \
	while $$_run_; do \
		find . -name "*.go" -type f | bin/entr -$(flags) $(MAKE) run; \
		sleep 0.1; \
	done ;\

.PHONY: lint
lint: bin/golangci-lint
	@bin/golangci-lint run

.PHONY: lint-fix
lint-fix: bin/golangci-lint
	@bin/golangci-lint run --fix

.PHONY: test
test: bin/gotestsum lint
	@echo ""
	@bin/gotestsum --format testdox -- -coverprofile=cover.out -coverpkg=./... $(shell go list ./... | grep -v /tools/ | grep -v /cmd/)
	@go tool cover -func=cover.out

cover.out:
	@if [ ! -f cover.out ]; then $(MAKE) test; fi

cover.txt: cover.out
	@go tool cover -func=cover.out -o cover.txt

.PHONY: cover.html
cover.html: cover.out
	@go tool cover -func=cover.out
	@go tool cover -html=cover.out -o cover.html
	@ex -sc '%s/<style>/<style>@import url("nord.css");/' -c 'x' cover.html

# - build and release

.PHONY: build
build: $(BUILD_TARGETS)

.PHONY: $(BUILD_TARGETS)
$(BUILD_TARGETS):
	@$(eval parts = $(subst -, ,$(subst $(BINARY_NAME),,$@)))
	@$(eval os = $(word 2, $(parts)))
	@$(eval arch = $(word 3, $(parts)))
	GOOS=$(os) GOARCH=$(arch) CGO_ENABLED=0 go build -ldflags "-s -w" -o $@ cmd/$(BINARY_NAME)/main.go

.PHONY: release
release: VERSION = $(shell go run cmd/$(BINARY_NAME)/main.go --responses $(RESPONSES_FILE) --version)
release: $(RELEASE_TARGETS)

.PHONY: $(RELEASE_TARGETS)
$(RELEASE_TARGETS): clean build
	@cp $(shell echo $@ | sed s/.tar.gz//) bin/$(BINARY_NAME)
	cd bin && tar -czf $(shell basename $@) $(BINARY_NAME)
	@rm bin/$(BINARY_NAME)

.PHONY: docker-build
docker-build:
	docker build $(PROJECT_DIR) -t $(BINARY_NAME):latest

.PHONY: docker-run
docker-run: docker-build
	docker run --rm $(BINARY_NAME):latest --version

# - tools

.PHONY: changelog
changelog: bin/git-chglog
	@echo ""
	@echo "generating changelog using next tag: $(next_tag):"
	@git tag -l | xargs git tag -d > /dev/null 2>&1
	@git fetch --tags > /dev/null 2>&1
	@bin/git-chglog --no-emoji -o CHANGELOG.md --next-tag $(next_tag)

# - ci checks

.PHONY: check
check: check-version check-cover check-commit

.PHONY: check-version
check-version:
	@echo ""
	@go run tools/versioncheck/main.go $(tag)

.PHONY: check-cover
check-cover: cover.txt
	@echo ""
	@cat cover.txt
	@go run tools/covercheck/main.go

.PHONY: check-commit
check-commit:
	@echo ""
	@go run tools/commitcheck/main.go '$(message)'

# - remote

.PHONY: remote-run
remote-run: build
	@echo ""
	@echo "running on $(host)"
	@ssh ubuntu@$(host) 'rm -rf /home/ubuntu/$(BINARY_NAME);'
	@scp bin/$(BINARY_NAME)-linux-amd64 ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)
	@scp .env ubuntu@$(host):/home/ubuntu/
	@ssh ubuntu@$(host) 'source /home/ubuntu/.env; /home/ubuntu/$(BINARY_NAME)'
	@ssh ubuntu@$(host) 'rm /home/ubuntu/.env /home/ubuntu/$(BINARY_NAME)'

.PHONY: remote-%-all
remote-%-all:
	@for host in $(REMOTE_HOSTS); do $(MAKE) remote-$* host=$$host; done

.PHONY: remote-install
remote-install: build
	@echo ""
	@echo "installing $(BINARY_NAME) on $(host)"
	@ssh ubuntu@$(host) 'rm -rf /home/ubuntu/$(BINARY_NAME); mkdir -p /home/ubuntu/$(BINARY_NAME)'
	@scp bin/$(BINARY_NAME)-linux-amd64 ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@scp systemd/$(BINARY_NAME).env     ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@scp systemd/$(BINARY_NAME).timer   ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@scp systemd/$(BINARY_NAME).service ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@scp systemd/install.sh             ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@ssh ubuntu@$(host) 'chmod +x /home/ubuntu/$(BINARY_NAME)/install.sh; /home/ubuntu/$(BINARY_NAME)/install.sh'

.PHONY: remote-uninstall
remote-uninstall:
	@echo ""
	@echo "uninstalling $(BINARY_NAME) from $(host)"
	@ssh ubuntu@$(host) 'rm -rf /home/ubuntu/$(BINARY_NAME); mkdir -p /home/ubuntu/$(BINARY_NAME)'
	@scp systemd/uninstall.sh  ubuntu@$(host):/home/ubuntu/$(BINARY_NAME)/
	@ssh ubuntu@$(host) 'chmod +x /home/ubuntu/$(BINARY_NAME)/uninstall.sh; /home/ubuntu/$(BINARY_NAME)/uninstall.sh'

# - rename cli

rename-cli: clean
	@echo ""
	@echo "renaming project to $(BINARY_NAME)"
	@find . \
	  -path ./.git -prune -o \
		-name Makefile -prune -o \
		-type f \
		-exec ex -sc '%s/cli-name/$(BINARY_NAME)/g' -c 'x' {} \;
	@mv cmd/cli-name cmd/$(BINARY_NAME)
	@git status

# - clean

.PHONY: clean
clean:
	rm -rf bin/*
	rm -rf cover.*
