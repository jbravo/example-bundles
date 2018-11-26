PROJECT         := bundles
ORG             := deislabs
DOCKER_REGISTRY ?= cnab

BASE_DIR        := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

GIT             ?= git
GIT_TAG         := $(shell $(GIT) describe --tags --always)
VERSION         ?= ${GIT_TAG}
# Replace + with -, for Docker image tag compliance
IMAGE_TAG       ?= $(subst +,-,$(VERSION))
BUNDLE          ?=
DUFFLE_IMG      ?= brigade.azurecr.io/deis/duffle:latest

ifeq ($(OS),Windows_NT)
	SHELL  = cmd.exe
	CHECK  = where.exe
else
	SHELL  ?= bash
	CHECK  ?= command -v
endif

HAS_DOCKER := $(shell $(CHECK) docker)
HAS_DUFFLE := $(shell $(CHECK) duffle)

.PHONY: has-docker
has-docker:
ifndef HAS_DOCKER
	$(error You must install docker)
endif

.PHONY: has-duffle
has-duffle:
ifndef HAS_DUFFLE
	$(error You must install duffle)
endif

# all loops through all sub-directories and if the file provided by the first argument exists,
# it will run the make target(s) provided by the second argument
define all
	@for dir in $$(ls -1); do \
		if [[ -e "$$dir/$(1)" ]]; then \
			BUNDLE=$$dir make $(2) ; \
		fi ; \
	done
endef

# run the provided make target on all bundles with a 'cnab/Dockerfile' file in their directory
define docker-all
	$(call all,cnab/Dockerfile,$(1))
endef

# run the provided make target on all bundles with a 'bundle.json' file in their directory
define bundle-all
	$(call all,bundle.json,$(1))
endef

.PHONY: check-bundle
check-bundle:
ifndef BUNDLE
	$(error BUNDLE must be provided, e.g., BUNDLE=<bundle> make <target>)
endif

.PHONY: docker-build
docker-build:
ifndef BUNDLE
	$(call docker-all,docker-build)
else 
	docker build -t $(DOCKER_REGISTRY)/$(BUNDLE):$(IMAGE_TAG) $(BUNDLE)/cnab
endif

.PHONY: docker-push
docker-push:
ifndef BUNDLE
	$(call docker-all,docker-push)
else
	docker push $(DOCKER_REGISTRY)/$(BUNDLE):$(IMAGE_TAG)
endif

.PHONY: docker-run
docker-run: check-bundle
	docker run -t $(DOCKER_REGISTRY)/$(BUNDLE):$(VERSION)

.PHONY: sign
sign: has-duffle
ifndef BUNDLE
	$(call bundle-all,sign)
else
	duffle bundle sign -f $(BUNDLE)/bundle.json
endif

.PHONY: sign-local
sign-local: has-duffle
ifndef BUNDLE
	$(call bundle-all,sign-local)
else
	duffle bundle sign -f $(BUNDLE)/bundle.json -o $(BUNDLE)/bundle.cnab
endif

# duffle commands in functional tests will run in insecure mode if this is set to 'true'
INSECURE ?= false

.PHONY: test-functional
test-functional:
ifeq ($(INSECURE),false)
	make sign-local
endif
	./scripts/test-functional.sh

.PHONY: test-functional-docker
test-functional-docker:
	docker run --rm \
		-v ${BASE_DIR}:/src \
		-w /src \
		-e BUNDLE=$(BUNDLE) \
		-e INSECURE=$(INSECURE) \
		-e CHECK=which \
		$(DUFFLE_IMG) sh -c 'duffle init -u "test@$(ORG)-$(PROJECT).com" && make test-functional'

