# Setting SHELL to bash allows bash commands to be executed by recipes.
export SHELL := /usr/bin/env bash -o pipefail
# Sets to exit when a recipe line exits non-zero/piped command fails.
export .SHELLFLAGS := -ec
# Sets terminal color support
export TERM=screen-256color

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
VERBOSE                      := echo
ARTIFACT_NAME                := gitlab-branch-source

# Release information
BUILD_DATE                   := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
MAJOR                        := 739
MINOR                        := 9999
PATCH                        := $(shell git rev-list HEAD --max-count=1 --abbrev-commit | tr -d '\n')
BUILD_ID                     ?= 0
RELEASE_VERSION              := $(shell echo -n $(MAJOR).$(MINOR).${BUILD_ID}-$(PATCH))

FROM_REPO_JAVA_MAVEN         := artifacts-we1.farfetch.net/docker-stable/farfetch/infrastructure-docker-maven
FROM_TAG_JAVA_MAVEN          := 3.9.6-21-jammy

#----------------------------------------------------------------------------------------------------------------------
# Linters, Getters & Helpers
#----------------------------------------------------------------------------------------------------------------------

get-major-tag:
	@echo -n $(MAJOR)
get-minor-tag:
	@echo -n $(MINOR)
get-patch-tag:
	@echo -n $(PATCH)
get-release-tag:
	@echo -n $(RELEASE_VERSION)


.PHONY: build
build:
	@docker compose build base $(NO_CACHE)

unit-tests: build
	@docker compose build unit-tests $(NO_CACHE)

packages:
	@docker compose build packages
