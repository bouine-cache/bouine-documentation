.PHONY: help serve build clean

help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

serve: ## Start local dev server with live reload.
	hugo server --buildDrafts --navigateToChanged

build: ## Build the static site to ./public.
	hugo --minify

clean: ## Remove build artifacts.
	rm -rf public resources
