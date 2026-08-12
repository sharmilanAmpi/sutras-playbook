DOCS_IMAGE := squidfunk/mkdocs-material

.PHONY: docs-serve docs-build docs-shell

docs-serve: ## Serve docs locally at http://localhost:8000 with live reload
	docker run --rm -it -p 8000:8000 -v $(CURDIR):/docs $(DOCS_IMAGE) serve -a 0.0.0.0:8000

docs-build: ## Build the static site into ./site
	docker run --rm -v $(CURDIR):/docs $(DOCS_IMAGE) build

docs-shell: ## Drop into a shell in the docs container
	docker run --rm -it -v $(CURDIR):/docs --entrypoint sh $(DOCS_IMAGE)
