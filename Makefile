SHELL = /bin/bash

include .make/all.mk

.PHONY: check-export
check-export: ## Check that the exported files are the files the action needs
	./tests/check_export.sh

.PHONY: test-shell
test-shell: ## Run the bats tests of the shell scripts
	@bats --version
	bats --recursive tests/bats

.PHONY: test
test: test-shell ## Run all the tests

.PHONY: all
all: format lint test ## Format, lint and test

.PHONY: clean
clean: ## Remove the local build output
	rm -rf dist build
