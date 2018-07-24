# Bring in additional environment variables (if the file exists)
# You can change files with `make ENV_FILE=dir/env-file <make-target>`
ENV_FILE ?= env/.env
-include $(ENV_FILE)
export

# Make sure our build directory is available.
BUILD_DIR ?= build
_create_build_dir := $(shell mkdir -p $(BUILD_DIR))

# Project settings
PROJECT := sphinx-confluence
PACKAGE := sphinx_confluence
EGG_INFO := $(subst -,_,$(PROJECT)).egg-info

# Python settings
ifndef PYTHON_MAJOR
	PYTHON_MAJOR := 2
	PYTHON_MINOR := 7
endif

# System paths
SYS_PYTHON := python$(PYTHON_MAJOR)
ifdef PYTHON_MINOR
	SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
endif
SYS_VIRTUALENV := virtualenv

# Use tox virtualenv if exists
ifdef VIRTUAL_ENV
	ENV := $(VIRTUAL_ENV)
else
	ENV := env/py$(PYTHON_MAJOR)$(PYTHON_MINOR)
endif

# File 'flag' to mark our dependencies as installed.
DEPENDS_DEV := $(ENV)/.depends-dev

# virtualenv path/executables
BIN := $(ENV)/bin
ACTIVATE := $(BIN)/activate
PYTHON := $(BIN)/python
PIP := $(BIN)/pip
TOX := $(BIN)/tox
NOSE := $(BIN)/nosetests

PYLINT := $(BIN)/pylint
FLAKE8 := $(BIN)/flake8
PEP8_IGNORED := E501

COVERAGE := $(BIN)/coverage
# http://coverage.readthedocs.io/en/coverage-4.2/cmd.html#data-file
COVERAGE_FILE=$(BUILD_DIR)/.coverage

# For reading HTML documentation.
OPEN := open

# Pip Cache
ifdef JENKINS_HOME
	PIP_CACHE_DIR := $(JENKINS_HOME)/.cache/pip
else ifdef VIRTUAL_ENV
	PIP_CACHE_DIR := $(VIRTUAL_ENV)/.cache/pip
else
	PIP_CACHE_DIR := .cache/pip
endif
PIP_CACHE := --cache-dir $(PIP_CACHE_DIR)

# CF configuration for publishing documentation.
CF_URL?=https://api.example.cloudfoundry.com
CF_ORG?=cf_org
CF_SPACE?=cf_space
CF_USER?=cf_user
CF_PASSWORD?=cf_password

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help.
	@IFS=$$'\n' ; \
	help_lines=(`fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/:/'`); \
	for help_line in $${help_lines[@]}; do \
		IFS=$$':' ; \
		help_split=($$help_line) ; \
		help_command=`echo $${help_split[0]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		help_info=`echo $${help_split[2]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		printf '\033[36m'; \
		printf "%-20s %s" $$help_command ; \
		printf '\033[0m'; \
		printf "%s\n" $$help_info; \
	done

.PHONY: all
all: test

## Dependencies ##

.PHONY: env
env: $(PIP)

$(PIP):
	$(SYS_VIRTUALENV) --python $(SYS_PYTHON) $(ENV)
	$(PIP) install wheel

.PHONY: depends
depends: ## Create virtual env and install requirements.
depends: .depends-dev

.PHONY: .depends-dev
.depends-dev: env Makefile $(DEPENDS_DEV)

$(DEPENDS_DEV): Makefile requirements.txt requirements-dev.txt
	$(PIP) install $(PIP_CACHE) -r requirements-dev.txt
	touch $(DEPENDS_DEV)  # flag to indicate dependencies are installed
	touch $(ENV_FILE)

## Cleaning ##

.PHONY: clean
clean:  ## Remove build artifacts.
clean:
	find $(PACKAGE) -name '*.pyc' -delete
	find $(PACKAGE) -name '__pycache__' -delete
	find . -name '.last_*' -delete
	rm -rf dist
	rm -rf docs/_build
	rm -rf $(EGG_INFO)
	rm -rf $(BUILD_DIR)/*
	rm -f $(COVERAGE_FILE)

.PHONY: clean-all
clean-all: ## Remove build artifacts, virtual env(s), and cache(s).
clean-all: clean clean-py27 clean-py36 clean-tox
	rm -rf $(PIP_CACHE_DIR)
	rm -rf .cache

clean-tox:
	rm -rf .tox

clean-py27:
	PYTHON_MAJOR=2 PYTHON_MINOR=7 $(MAKE) .clean-env
clean-py36:
	PYTHON_MAJOR=3 PYTHON_MINOR=6 $(MAKE) .clean-env

.PHONY: .clean-env
.clean-env:
	rm -rf $(ENV)

## Code Analysis ##

.PHONY: lint
lint: ## Run code analysis.
lint: flake8

.PHONY: flake8
flake8: .depends-dev
	$(FLAKE8) $(PACKAGE) setup.py --ignore=$(PEP8_IGNORED) --output-file=$(BUILD_DIR)/flake8-lint.txt --tee

.PHONY: pylint
pylint: .depends-dev
	$(PYLINT) $(PACKAGE)

## Testing ##

.PHONY: test
test: ## Run automated tests (unit/functional).
test: .depends-dev
test:
	$(NOSE) tests/ --with-xcoverage --xcoverage-file=$(BUILD_DIR)/coverage.xml --cover-erase --cover-package=$(PACKAGE) --verbose --with-xunit --xunit-file=$(BUILD_DIR)/xunit.xml
	@find . -name '.last_*' -delete

test-all: ## Run automated tests on all configured Python versions.
test-all: tox.ini
	[ -f /.dockerenv ] && $(TOX) || $(TOX) --skip-missing-interpreters

## Coverage ##

.PHONY: cov-report
cov-report: ## View test coverage.
cov-report: test
	$(COVERAGE) html
	$(OPEN) $(BUILD_DIR)/htmlcov/index.html

## Building ##

.PHONY: build
build: ## Lint code, run automated tests, and compute coverage.
build: lint test-all

## Documentation ##

.PHONY: docs
docs: ## Generate documentation.
docs: .depends-dev
	. $(ACTIVATE); cd docs; $(MAKE) html

.PHONY: read
read: ## Read documentation.
read: docs
	$(OPEN) docs/_build/html/index.html

.PHONY: publish
publish: ## Publish documentation.  (Requires CF_* environment variables.)
publish: docs
	cd docs/_build/html; touch Staticfile;
	cd docs/_build/html; cf login -a $(CF_URL) -u $(CF_USER) -p $(CF_PASSWORD) -o $(CF_ORG) -s $(CF_SPACE);
	cd docs/_build/html; cf push cf-broker-api-docs

## Release ##

.PHONY: dist
dist: clean build
	$(PYTHON) setup.py sdist
	$(PYTHON) setup.py bdist_wheel

.PHONY: upload
upload: ## Upload package to internal PyPI server.
upload: clean build
	$(PYTHON) setup.py sdist upload -r pypicloud
	$(PYTHON) setup.py bdist_wheel upload -r pypicloud