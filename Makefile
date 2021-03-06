NAME        := git-ghost
PROJECTROOT := $(shell pwd)
VERSION     := $(shell cat ${PROJECTROOT}/VERSION)
REVISION    := $(shell git rev-parse --short HEAD)
IMAGE_PREFIX ?= dtaniwaki/
IMAGE_TAG   ?= $(VERSION)
OUTDIR      ?= $(PROJECTROOT)/dist
RELEASE_TAG ?=
GITHUB_API  ?=
GITHUB_USER ?=
GITHUB_REPO ?=
GITHUB_TOKEN ?=
DOCKER_GITHUB_ENV_FLAGS := -e GITHUB_API=$(GITHUB_API) -e GITHUB_USER=$(GITHUB_USER) -e GITHUB_REPO=$(GITHUB_REPO) -e GITHUB_TOKEN=$(GITHUB_TOKEN)

LDFLAGS := -ldflags="-s -w -X \"github.com/pfnet-research/git-ghost/cmd.Version=$(VERSION)\" -X \"github.com/pfnet-research/git-ghost/cmd.Revision=$(REVISION)\" -extldflags \"-static\""

guard-%:
	@ if [ "${${*}}" = "" ]; then \
    echo "Environment variable $* is not set"; \
		exit 1; \
	fi

.PHONY: build
build: deps
	go build -tags netgo -installsuffix netgo $(LDFLAGS) -o $(OUTDIR)/$(NAME)

.PHONY: install
install:
	go install -tags netgo -installsuffix netgo $(LDFLAGS)

.PHONY: build-linux-amd64
build-linux-amd64:
	make build \
		GOOS=linux \
		GOARCH=amd64 \
		NAME=git-ghost-linux-amd64

.PHONY: build-linux
build-linux: build-linux-amd64

.PHONY: build-darwin
build-darwin:
	make build \
		GOOS=darwin \
		NAME=git-ghost-darwin-amd64

.PHONY: build-windows
build-windows:
	make build \
		GOARCH=amd64 \
		GOOS=windows \
		NAME=git-ghost-windows-amd64.exe

.PHONY: build-all
build-all: build-linux build-darwin build-windows

.PHONY: release
release: release-code release-assets release-image

.PHONY: release-code
release-code: guard-RELEASE_TAG guard-GITHUB_USER guard-GITHUB_REPO guard-GITHUB_TOKEN
	github-release release --tag $(RELEASE_TAG)

.PHONY: release-assets
release-assets: guard-RELEASE_TAG guard-GITHUB_USER guard-GITHUB_REPO guard-GITHUB_TOKEN clean build-all
	for target in linux-amd64 darwin-amd64 windows-amd64.exe; do \
		github-release upload \
			--tag $(RELEASE_TAG) \
			--name git-ghost-$$target \
			--file $(OUTDIR)/git-ghost-\$$target; \
	done

.PHONY: release-image
release-image: IMAGE_TAG=$(RELEASE_TAG)
release-image: guard-RELEASE_TAG build-image-cli
	docker push $(IMAGE_PREFIX)git-ghost-cli:$(RELEASE_TAG)

.PHONY: lint
lint: deps
	golangci-lint run --config golangci.yml

.PHONY: deps
deps:
	dep ensure

.PHONY: build-image-dev
build-image-dev:
	docker build -t $(IMAGE_PREFIX)git-ghost-dev:$(IMAGE_TAG) --target git-ghost-dev $(PROJECTROOT)

.PHONY: build-image-cli
build-image-cli:
	docker build -t $(IMAGE_PREFIX)git-ghost-cli:$(IMAGE_TAG) --target git-ghost-cli $(PROJECTROOT)

.PHONY: build-image-all
build-image-all: build-image-dev build-image-cli

test: deps
	@go test -v -race -short -tags no_e2e ./...

.PHONY: shell
shell: build-image-cli
	docker run -it $(IMAGE_PREFIX)git-ghost-cli:$(IMAGE_TAG) bash

.PHONY: dev-shell
dev-shell: build-image-dev
	docker run -it $(IMAGE_PREFIX)git-ghost-dev:$(IMAGE_TAG) bash

.PHONY: e2e
e2e:
	@go test -v $(PROJECTROOT)/test/e2e/e2e_test.go

.PHONY: docker-e2e
docker-e2e: build-image-dev
	@docker run $(IMAGE_PREFIX)git-ghost-dev:$(IMAGE_TAG) make install e2e DEBUG=$(DEBUG)

.PHONY: update-license
update-license:
	@python3 ./scripts/license/add.py -v

.PHONY: check-license
check-license:
	@python3 ./scripts/license/check.py -v

.PHONY: coverage
coverage:
	@go test -tags no_e2e -covermode=count -coverprofile=profile.cov -coverpkg ./pkg/...,./cmd/... $(shell go list ./... | grep -v /vendor/)
	@go tool cover -func=profile.cov

.PHONY: clean
clean:
	rm -rf dist/*
