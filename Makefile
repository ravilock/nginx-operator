# Path to Docker binary
DOCKER ?= docker
# Docker image name
IMAGE ?= tsuru/nginx-operator
# Docker image revision
TAG ?= ${VERSION}

KUBECTL ?= kubectl

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

VERSION    ?= main
GIT_COMMIT ?= $(shell git rev-list -1 HEAD)

GO_BUILD_FLAGS = GO111MODULE=on CGO_ENABLED=0
GO_LDFLAGS     = "-X=github.com/tsuru/nginx-operator/version.Version=$(VERSION) -X=github.com/tsuru/nginx-operator/version.GitCommit=$(GIT_COMMIT)"

.PHONY: test
test: generate
	go test -race -cover ./...

.PHONY: lint
lint: golangci-lint
	$(GOLANGCI_LINT) run -c .golangci.yml ./...

.PHONY: build
build: manager

.PHONY: manager
manager: generate
	${GO_BUILD_FLAGS} go build -ldflags $(GO_LDFLAGS) -o bin/nginx-operator main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
.PHONY: run
run: generate manifests
	go run ./main.go --enable-leader-election=false

# Install CRDs into a cluster
.PHONY: install
install: manifests kustomize
	kubectl apply -k config/crd

# Uninstall CRDs from a cluster
.PHONY: uninstall
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
.PHONY: deploy
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMAGE):$(TAG)
	$(KUBECTL) apply -k config/default

# Build the docker image
.PHONY: docker-build
docker-build:
	$(DOCKER) build --build-arg VERSION=${VERSION} --build-arg GIT_COMMIT=${GIT_COMMIT} . -t $(IMAGE):$(TAG)

# Push the docker image
.PHONY: docker-push
docker-push:
	$(DOCKER) push $(IMAGE):$(TAG)

# Generate manifests e.g. CRD, RBAC etc.
.PHONY: manifests
manifests: controller-gen
	$(CONTROLLER_GEN) rbac:roleName=role crd paths=./... output:crd:artifacts:config=config/crd/bases

# Generate code (zz_generated.deepcopy.go files)
.PHONY: generate
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

# find or download controller-gen
# download controller-gen if necessary
.PHONY: controller-gen
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	go install sigs.k8s.io/controller-tools/cmd/controller-gen@v0.15.0 ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

# find or download kustomize
# download kustomize if necessary
.PHONY: kustomize
kustomize:
ifeq (, $(shell which kustomize))
	@{ \
	set -e ;\
	KUSTOMIZE_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$KUSTOMIZE_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go install sigs.k8s.io/kustomize/kustomize/v3@v3.5.4 ;\
	rm -rf $$KUSTOMIZE_GEN_TMP_DIR ;\
	}
KUSTOMIZE=$(GOBIN)/kustomize
else
KUSTOMIZE=$(shell which kustomize)
endif

# find or download golangci-lint
# download golangci-lint if necessary
.PHONY: golangci-lint
golangci-lint:
ifeq (, $(shell which golangci-lint))
	@{ \
	set -e ;\
	curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOBIN) ;\
	}
GOLANGCI_LINT=$(GOBIN)/golangci-lint
else
GOLANGCI_LINT=$(shell which golangci-lint)
endif
