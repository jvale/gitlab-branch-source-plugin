# Setting SHELL to bash allows bash commands to be executed by recipes.
export SHELL := /usr/bin/env bash -o pipefail
# Sets to exit when a recipe line exits non-zero/piped command fails.
export .SHELLFLAGS := -ec
# Sets terminal color support
export TERM=screen-256color

BOLD=$(shell tput -T linux bold)
RED=$(shell tput -T linux setaf 1)
GREEN=$(shell tput -T linux setaf 2)
YELLOW=$(shell tput -T linux setaf 3)
CYAN=$(shell tput -T linux setaf 6)
MAGENTA=$(shell tput -T linux setaf 5)
BLUE=$(shell tput -T linux setaf 4)
RESET=$(shell tput -T linux sgr0)

# Message shortcuts
GEAR=$(CYAN)$(BOLD) ⚙ $(RESET)
INFO=$(CYAN)$(BOLD) ℹ $(RESET)
ERROR=$(RED)$(BOLD) ✖ $(RESET)
DEBUG=$(BLUE)$(BOLD)  $(RESET)

# Line separator
SEPARATOR := $(shell printf "=========================================================================================\n")

ifeq (, $(shell which docker))
$(error $(ERROR) $(RED) No docker in $(PATH), ensure you have a compatible docker cli installed $(RESET) $(ERROR))
endif

ifeq ($(or $(REGISTRY_USERNAME),$(REGISTRY_API_KEY)),)
-include .env
export
endif

# Docker and buildkit settings
# As distroless needs a local image, this is required to work with M1 processors
DOCKER_BUILDKIT          := 1
BUILDKIT_COLORS          := run=green:warning=yellow:error=red:cancel=255,165,0
BUILDKIT_PROGRESS        := plain
PLATFORM                 := "linux/amd64" # As distroless need a local image, this is required to work in M1 processors

ifeq (, $(shell which docker))
	$(error "No docker in $(PATH), ensure you have a compatible docker cli installed")
endif
## Debug setting as true disables images caching, and print additional messages, should be avoided in pipeline
## and mostly used during local development
ifeq ($(DEBUG_MODE), true)
VERBOSE  := set -x
NO_CACHE := --no-cache
BUILDKIT_PROGRESS:=plain
endif
# Using BUILD_ID environment variable in order to conditionally disable build cache locally,
# BUILD_ID exists on the pipeline and shouldn't be defined on your local development environment
# ifdef BUILD_ID
# DEBUG_MODE:=false
# BUILDKIT_PROGRESS:=plain
# endif

#----------------------------------------------------------------------------------------------------------------------
# Global variables
#----------------------------------------------------------------------------------------------------------------------
.EXPORT_ALL_VARIABLES:
CWD                          := $(shell pwd)
PACKAGE_FOLDERS              := $(CWD)/exportedPackages
VERBOSE                      := echo
REGISTRY_URL                 := artifacts-we1.farfetch.net
REGISTRY_DOCKER_BETA         := $(REGISTRY_URL)/docker-beta/farfetch
REGISTRY_DOCKER_STABLE       := $(REGISTRY_URL)/docker-stable/farfetch
REGISTRY_DOCKER_DROPZONE     := $(REGISTRY_URL)/docker-dropzone/farfetch
REGISTRY_DOCKERIO            := $(REGISTRY_URL)/dockerio-docker-all-we1
ARTIFACT_NAME                := docs-declarative-examples
FROM_SCRATCH_REPO            := artifacts-we1.farfetch.net/docker-stable/farfetch/infrastructure-docker-scratch
FROM_SCRATCH_TAG             := latest
FFUSER_UID                   := 60000
# Release information
BUILD_DATE                   := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_AUTHOR                   := $(shell git log -1 --pretty=format:'%ae')
GIT_COMMIT                   := $(shell git rev-parse HEAD || echo unknown)
GIT_BRANCH                   := $(shell git rev-parse --symbolic-full-name --verify --quiet --abbrev-ref HEAD)
GIT_TAG                      := $(shell git describe --exact-match --tags --abbrev=0  2> /dev/null || echo untagged)
GIT_TREE_STATE               := $(shell if [ -z "`git status --porcelain`" ]; then echo "clean" ; else echo "dirty"; fi)
GIT_REPO_URL                 := https://gitlab.global.farfetch-corp.net/technology/declarative-pipeline-examples
MAJOR                        := 0
MINOR                        := 1
PATCH                        := $(shell git rev-list HEAD --max-count=1 --abbrev-commit | tr -d '\n')
BUILD_ID                     ?= 0
RELEASE_VERSION              := $(shell echo -n $(MAJOR).$(MINOR).0-$(PATCH)-${BUILD_ID})
# Ubuntu 22.04 - Jammy
JAMMY_TAG_IMAGE              := jammy
JAMMY_TAG_RELEASE            := 22.04
JAMMY_EOL                    := 2027-05-01
JAMMY_OS_PACKAGES            := "ca-certificates locales gpgconf gpg gpg-agent gnupg-utils wget unzip"
JAMMY_OS_PACKAGES_EXTRA      := "libc6 libgcc1 libgssapi-krb5-2 libicu-dev liblttng-ust1 libstdc++6 zlib1g tzdata libgnutls28-dev"
# Dotnet 8
FROM_REPO_DOTNET8_SDK        := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-dotnet-sdk
FROM_TAG_DOTNET8_SDK         := 8.0
FROM_REPO_DOTNET8_ASPNET     := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-dotnet-aspnet
FROM_TAG_DOTNET8_ASPNET      := 8.0
# NodeJS
FROM_REPO_NODEJS22            := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-nodejs
FROM_TAG_NODEJS22             := 22-noble
# Java
FROM_REPO_JAVA_JDK            := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-openjdk-jdk
FROM_TAG_JAVA_JDK             := 21-jammy
FROM_REPO_JAVA_JRE            := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-openjdk-jre
FROM_TAG_JAVA_JRE             := 21-jammy
FROM_REPO_JAVA_MAVEN          := $(REGISTRY_DOCKER_STABLE)/infrastructure-docker-maven
FROM_TAG_JAVA_MAVEN           := 3.9.6-21-jammy

# Xray
XRAY_ARGS                    := "--fixable-only --watches SCA_PCI_Security_Watch --bypass-archive-limits"
#----------------------------------------------------------------------------------------------------------------------
##@ Targets
#----------------------------------------------------------------------------------------------------------------------

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ \
	{ printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' \
	$(MAKEFILE_LIST)

.PHONY: creds
creds: ## Setup registry credentials from environment
	@echo -n "$(REGISTRY_NPM_TOKEN)" > .pipeline/.art_creds_npm_token \
	&& echo -n "$(REGISTRY_USERNAME)" > .pipeline/.art_creds_username \
	&& echo -n "$(REGISTRY_API_KEY)" > .pipeline/.art_creds_token \
	&& echo -n "$(REGISTRY_USERNAME):$(REGISTRY_API_KEY)" > .pipeline/.art_creds

#----------------------------------------------------------------------------------------------------------------------
# Linters, Getters & Helpers
#----------------------------------------------------------------------------------------------------------------------

env-info: ## Display overall environment information
	@./.pipeline/scripts/env_info.sh dotnet

.PHONY: lint
lint: ## Run linter
	@echo $(GIT_COMMIT)
	@$(CWD)/.pipeline/scripts/hadolint.sh

.PHONY: jenkinsfile-lint
jenkinsfile-lint: ## Jenkinsfile linter
	@docker run --rm \
		--platform=$(PLATFORM) \
  	-v $(CWD):/mnt/src \
		$(REGISTRY_DOCKER_STABLE)/infrastructure-buildtest-jenkinsfilescan:1.1 \
    -d /mnt/src

.PHONY: xray
xray: xray-jammy xray-focal  ## Xray vulnerability scan on all images

.PHONY: xray-jammy
xray-jammy: ## Xray vulnerability scan on Jammy image
	@echo "$(SEPARATOR) $(GEAR) $(GREEN) Scanning Ubuntu Jammy image $(RESET)  $(GEAR) $(SEPARATOR)" && \
	jf docker scan $(ARTIFACT_NAME):$(JAMMY_TAG_IMAGE) $(shell echo $(XRAY_ARGS) |  tr -d '"')

.PHONY: xray-focal
xray-focal: ## Xray vulnerability scan on Jammy image
	@echo "$(SEPARATOR) $(GEAR) $(GREEN) Scanning Ubuntu Focal image $(RESET) $(GEAR) $(SEPARATOR)" && \
	jf docker scan $(ARTIFACT_NAME):$(FOCAL_TAG_IMAGE) $(shell echo $(XRAY_ARGS) |  tr -d '"')

get-major-tag:
	@echo -n $(MAJOR)
get-minor-tag:
	@echo -n $(MINOR)
get-patch-tag:
	@echo -n $(PATCH)
get-release-tag:
	@echo -n $(RELEASE_VERSION)

define export-packages ## This function helps exporting a package from a target image
	$(eval IMAGE_ID = $(shell docker images -q packages 2> /dev/null))
	$(warning  $(INFO) $(YELLOW) Exporting packages from $(IMAGE_ID) $(RESET) $(INFO))
	mkdir -p "$(PACKAGE_FOLDERS)"
	docker rm packages || true
	docker create --name=packages packages -v $(CWD)/exportedPackages
	docker export packages -o packages.tar
	tar xf packages.tar -C $(CWD)/exportedPackages/
	rm -rf packages.tar || true
	ls -ltr $(CWD)/exportedPackages/
endef



.PHONY: build
build: creds
	@docker compose build $(NO_CACHE)

test-java-hello-world: ## Run java example app
	@docker compose build unit-tests --no-cache

stop-java-hello-world: ## Stop java example app
	@docker compose down --remove-orphans

# pack-java-hello-world:
# 	@$(call export-packages)
