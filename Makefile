.PHONY: help install serve build build-versioned serve-versioned version clean docker-build docker-push auth-registry deploy

CONTAINER   := rg.fr-par.scw.cloud/heula/bouine-documentation
TAG         := latest
BOUINE_INFRA := ../bouine-infra
NAMESPACE   := thylong-innerspace

help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install Node dependencies required by Doks.
	npm install

serve: ## Start local dev server with all doc versions (archived pre-built, latest live).
	./scripts/serve.sh

build: ## Build the static site to ./public.
	npm run build

build-versioned: ## Build all documentation versions (latest + archived) to ./public.
	./scripts/build-versioned.sh public

serve-versioned: ## Build and serve all versions locally on :1313.
	./scripts/build-versioned.sh public
	python3 -m http.server 1313 --directory public

version: ## Cut a new docs version after a bouine minor/major release. Usage: make version V=0.5
	@if [ -z "$$V" ]; then echo "Usage: make version V=<new-minor-version>"; echo "Example: make version V=0.5"; exit 1; fi
	./scripts/version.sh "$$V"

clean: ## Remove build artifacts.
	rm -rf public resources

docker-build: ## Build the container image with all doc versions (linux/amd64).
	git submodule update --init
	./scripts/build-versioned.sh public
	docker buildx build --platform linux/amd64 -t $(CONTAINER):$(TAG) --load .

auth-registry: ## Authenticate Docker to the Scaleway registry (needs SCW_ACCESS_KEY and SCW_SECRET_KEY).
	@echo $$SCW_SECRET_KEY | docker login rg.fr-par.scw.cloud -u $$SCW_ACCESS_KEY --password-stdin

docker-push: docker-build ## Build and push the image to the registry.
	docker push $(CONTAINER):$(TAG)

deploy: docker-push ## Push the image and roll the deployment in the k3s cluster.
	kubectl apply -k $(BOUINE_INFRA)/k8s/
	kubectl rollout restart deployment/bouine-docs -n $(NAMESPACE)
	kubectl rollout status deployment/bouine-docs -n $(NAMESPACE) --timeout=120s
