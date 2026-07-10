.PHONY: help install serve build clean docker-build docker-push auth-registry deploy

CONTAINER   := rg.fr-par.scw.cloud/heula/bouine-documentation
TAG         := latest
BOUINE_INFRA := ../../bouine-infra
NAMESPACE   := thylong-innerspace

help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install Node dependencies required by Doks.
	npm install

serve: ## Start local dev server with live reload.
	npm run dev

build: ## Build the static site to ./public.
	npm run build

clean: ## Remove build artifacts.
	rm -rf public resources

docker-build: ## Build the container image (linux/amd64).
	git submodule update --init
	docker buildx build --platform linux/amd64 -t $(CONTAINER):$(TAG) --load .

auth-registry: ## Authenticate Docker to the Scaleway registry (needs SCW_SECRET_KEY).
	@echo $$SCW_SECRET_KEY | docker login rg.fr-par.scw.cloud -u nologin --password-stdin

docker-push: docker-build ## Build and push the image to the registry.
	docker push $(CONTAINER):$(TAG)

deploy: docker-push ## Push the image and roll the deployment in the k3s cluster.
	kubectl apply -k $(BOUINE_INFRA)/k8s/
	kubectl rollout restart deployment/bouine-docs -n $(NAMESPACE)
	kubectl rollout status deployment/bouine-docs -n $(NAMESPACE) --timeout=120s
