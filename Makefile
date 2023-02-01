# SPDX-FileCopyrightText: 2022-present Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

SHELL = bash -e -o pipefail

export CGO_ENABLED=1
export GO111MODULE=on

.PHONY: build

TOPO_DISCOVERY_VERSION ?= latest

build-tools:=$(shell if [ ! -d "./build/build-tools" ]; then mkdir -p build && cd build && git clone https://github.com/onosproject/build-tools.git; fi)
include ./build/build-tools/make/onf-common.mk

mod-update: # @HELP Download the dependencies to the vendor folder
	go mod tidy
	go mod vendor

mod-lint: mod-update # @HELP ensure that the required dependencies are in place
	# dependencies are vendored, but not committed, go.sum is the only thing we need to check
	bash -c "diff -u <(echo -n) <(git diff go.sum)"

build: # @HELP build the Go binaries and run all validations (default)
build: mod-update
	go build -mod=vendor -o build/_output/topo-discovery ./cmd/topo-discovery

test: # @HELP run the unit tests and source code validation producing a golang style report
test: mod-lint build linters license
	go test -race github.com/onosproject/topo-discovery/...

jenkins-test: # @HELP run the unit tests and source code validation producing a junit style report for Jenkins
jenkins-test: jenkins-tools mod-lint build linters license
	TEST_PACKAGES=github.com/onosproject/topo-discovery/... ./build/build-tools/build/jenkins/make-unit

integration-tests: integration-test-namespace # @HELP run helmit integration tests locally
	make basic -C test

topo-discovery-docker:  # @HELP build topo-discovery base Docker image
	docker build --platform linux/amd64 . -f build/topo-discovery/Dockerfile \
		-t ${DOCKER_REPOSITORY}topo-discovery:${TOPO_DISCOVERY_VERSION}

images: # @HELP build all Docker images
images: mod-update topo-discovery-docker

docker-push-latest: docker-login
	docker push onosproject/topo-discovery:latest

kind: # @HELP build Docker images and add them to the currently configured kind cluster
kind: images kind-only

kind-only: # @HELP deploy the image without rebuilding first
kind-only:
	@if [ "`kind get clusters`" = '' ]; then echo "no kind cluster found" && exit 1; fi
	kind load docker-image --name ${KIND_CLUSTER_NAME} ${DOCKER_REPOSITORY}topo-discovery:${TOPO_DISCOVERY_VERSION}

all: build images

publish: # @HELP publish version on github and dockerhub
	./build/build-tools/publish-version ${VERSION} onosproject/topo-discovery

jenkins-publish: images docker-push-latest # @HELP Jenkins calls this to publish artifacts
	./build/build-tools/release-merge-commit
	./build/build-tools/build/docs/push-docs

clean:: # @HELP remove all the build artifacts
	rm -rf ./build/_output ./vendor ./cmd/topo-discovery/topo-discovery ./cmd/onos/onos
	go clean -testcache github.com/onosproject/topo-discovery/...