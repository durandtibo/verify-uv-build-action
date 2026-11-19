SHELL = /bin/bash

include .make/help.mk
include .make/actions.mk
include .make/git.mk
include .make/github.mk
include .make/makefile.mk
include .make/markdown.mk
include .make/self.mk
include .make/shell.mk
include .make/toml.mk
include .make/tools.mk
include .make/uv.mk
include .make/yaml.mk

.DEFAULT_GOAL := help

.PHONY: install-tools
install-tools: install-prettier install-yamllint install-mbake install-checkmake install-shellcheck install-shfmt install-bats install-taplo install-markdownlint install-actionlint install-gh ## Install all formatting/linting tools

.PHONY: format
format: format-yaml format-makefile format-shell format-toml format-markdown ## Format all files

.PHONY: lint
lint: lint-yaml lint-makefile lint-shell lint-markdown lint-actions ## Lint all files

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
