SHELL := /bin/bash

.PHONY: fmt lint

fmt:
	terraform -chdir=terraform fmt -recursive

lint:
	@echo "Add tflint/kubeval if you want"
