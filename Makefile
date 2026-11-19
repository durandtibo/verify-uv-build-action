SHELL = /bin/bash

include .make/all.mk

.PHONY: lint-bats
lint-bats: ## Check that the bats assertions do not pass vacuously on bash 3.2
	./tests/check_bats_assertions.sh tests/bats

.PHONY: mutation-check
mutation-check: ## Check that the bats tests detect deliberate breakages of the scripts
	./tests/mutation_check.sh

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
all: format lint lint-bats test ## Format, lint and test

.PHONY: clean
clean: ## Remove the local build output
	rm -rf dist build
