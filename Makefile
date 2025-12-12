SHELL=/bin/bash

.PHONY : format
format :
	markdownlint **/*.md
	prettier --write .
	yamllint -f colored .
