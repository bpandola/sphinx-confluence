# Python settings
ifndef PYTHON_MAJOR
	PYTHON_MAJOR := 2
endif
ifndef PYTHON_MINOR
	PYTHON_MINOR := 7
endif
ENV := env/py$(PYTHON_MAJOR)$(PYTHON_MINOR)

# Project settings
PROJECT := test-service-broker
PACKAGE := broker

# System paths
PLATFORM := $(shell python -c 'import sys; print(sys.platform)')
ifneq ($(findstring win32, $(PLATFORM)), )
	SYS_PYTHON_DIR := C:\\Python$(PYTHON_MAJOR)$(PYTHON_MINOR)
	SYS_PYTHON := $(SYS_PYTHON_DIR)\\python.exe
	SYS_VIRTUALENV := $(SYS_PYTHON_DIR)\\Scripts\\virtualenv.exe
else
	SYS_PYTHON := python$(PYTHON_MAJOR)
	ifdef PYTHON_MINOR
		SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
	endif
	SYS_VIRTUALENV := virtualenv
endif

# virtualenv paths
ifneq ($(findstring win32, $(PLATFORM)), )
	BIN := $(ENV)/Scripts
	OPEN := cmd /c start
else
	BIN := $(ENV)/bin
	ifneq ($(findstring cygwin, $(PLATFORM)), )
		OPEN := cygstart
	else
		OPEN := open
	endif
endif

# virtualenv executables
PYTHON := $(BIN)/python
PIP := $(BIN)/pip
NOSE := $(BIN)/nosetests
FLAKE8 := $(BIN)/flake8
COVERAGE := $(BIN)/coverage
ACTIVATE := $(BIN)/activate

# Remove if you don't want pip to cache downloads
PIP_CACHE_DIR := .cache
PIP_CACHE := --download-cache $(PIP_CACHE_DIR)

# Flags for PHONY targets
DEPENDS_DEV := $(ENV)/.depends-dev
ENVVARS_DEV := $(ENV)/.envvars-dev

# Bring in additional env vars (if the file exists)
-include $(ENVVARS_DEV)

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
$(DEPENDS_DEV): Makefile requirements-dev.txt requirements.txt
	$(PIP) install -r requirements-dev.txt
	touch $(DEPENDS_DEV)  # flag to indicate dependencies are installed

$(ENVVARS_DEV): Makefile
	touch $(ENVVARS_DEV)

## Cleaning ##

.PHONY: clean
clean:  ## Remove build artifacts.
clean: .clean-test .clean-lint
	find $(PACKAGE) -name '*.pyc' -delete
	find $(PACKAGE) -name '__pycache__' -delete
	find . -name '.last_*' -delete
	rm -rf dist build
	rm -rf docs/_build
	rm -rf $(EGG_INFO)

.PHONY: clean-all
clean-all: ## Remove build artifacts as well as virtual env.
clean-all: clean
	rm -rf $(PIP_CACHE_DIR)
	rm -rf $(ENV)
	find . -name '.aws_config' -delete

.PHONY: .clean-test
.clean-test:
	rm -rf .coverage htmlcov xunit.xml coverage.xml

.PHONY: .clean-lint
.clean-lint:
	find . -name 'flake8-lint.txt' -delete

## Code Analysis ##

.PHONY: lint
lint: ## Run code analysis.
lint: flake8

PEP8_IGNORED := E501

.PHONY: flake8
flake8: .depends-dev
	$(FLAKE8) $(PACKAGE) tests --ignore=$(PEP8_IGNORED) --output-file=flake8-lint.txt --tee

## Testing ##

.PHONY: test
test: ## Run automated tests.
test: .depends-dev .clean-test
test:
	export BROKER_CONFIG=TestingConfig; $(NOSE) tests --nologcapture --with-xcoverage --cover-package=$(PACKAGE) --verbose --with-xunit --xunit-file=xunit.xml

test-all: test-py27
test-py27:
	PYTHON_MAJOR=2 PYTHON_MINOR=7 $(MAKE) test

.PHONY: htmlcov
htmlcov: ## View test coverage.
htmlcov: test
	$(COVERAGE) html
	$(OPEN) htmlcov/index.html

## Building ##

.PHONY: build
build: ## Lint code, run automated tests, and compute coverage.
build: test lint

## Running ##

.PHONY: run
run: ## Run broker locally in development mode.
run: .depends-dev
	export BROKER_CONFIG=DevelopmentConfig; $(PYTHON) run.py

## Documentation ##

.PHONY: docs
docs: ## Generate documentation.
docs: .depends-dev
	. $(ACTIVATE); cd docs; $(MAKE) html
	#. $(ACTIVATE); cd docs; $(MAKE) confluence

.PHONY: read
read: ## Read documentation.
read: docs
	. $(ACTIVATE); cd docs; conf_publisher pub_config_dev.yml --auth $(CONFLUENCE_AUTH) --verbose
	$(OPEN) https://healthsuite.atlassian.net/wiki/x/uwDzC

## Deploying ##

.PHONY: cf-deploy
cf-deploy: ## Deploy to Cloud Foundry
cf-deploy: build
	cf login -a $(CF_URL) -u $(CF_USER) -p $(CF_PASSWORD) -o $(CF_ORG) -s $(CF_SPACE)
	cf blue-green-deploy $(PROJECT) --smoke-test tests/smoketests/smoketest.py

.PHONY: jenkins-deploy
jenkins-deploy: ## Deploy to Cloud Foundry via Jenkins.
jenkins-deploy: test
ifeq ($(JENKINS_HOME),)
	$(error Not running on Jenkins server)
endif
	$(BIN)/jenkins-deploy-broker
