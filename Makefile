.PHONY: help install serve build clean

help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

install: ## Install Node dependencies required by Doks.
	npm install

serve: ## Start local dev server with live reload.
	npm run dev

build: ## Build the static site to ./public.
	npm run build

clean: ## Remove build artifacts.
	rm -rf public resources
