define HELP

This Makefile contains build and test commands for the example_project

Usage:

make help          - Show this message
make clean         - Remove generated files
make runserver     - Run the django server
make requirements     - Install requirements from requirements.txt
make makemigrations appname=blah	- Create migration file(s) for app
make migrate_all	- Run all pending migrations
make migrate_zero appname=blah	- Unapply all migrations for app
make shell			- Start a python session with django stuff loaded
make dbshell		- Start a database command shell
make createsuperuser - Create a new app superuser in the db
make lint			- Lint code
endef

export HELP

PROJECT_NAME="example_project"

.PHONY: help
help:
	@echo "$$HELP"

.PHONY: clean
clean:
	find . -name '*.pyc' -delete
	rm -f npm-debug.log
	rm -rf node_modules
	rm -f lint.txt
	rm -rf build
	rm -f $(REQUIREMENTS_RESULT)

.PHONY: lint
lint: requirements
	flake8 $(PROJECT_NAME) | tee lint.txt

.PHONY: npminstall
npminstall:
	npm install

.PHONY: requirements
requirements:
	pip install -r requirements.txt

.PHONY: runserver
runserver: requirements
	python $(PROJECT_NAME)/manage.py runserver 0.0.0.0:8000

.PHONY: makemigrations
makemigrations: requirements
	python $(PROJECT_NAME)/manage.py makemigrations $(appname)

.PHONY: migrate_all
migrate_all: requirements
	python $(PROJECT_NAME)/manage.py migrate

.PHONY: migrate
migrate: requirements
	python $(PROJECT_NAME)/manage.py migrate $(appname)

.PHONY: migrate_zero
migrate_zero: requirements
	python $(PROJECT_NAME)/manage.py migrate $(appname) zero

.PHONY: shell
shell: requirements
	python $(PROJECT_NAME)/manage.py shell

.PHONY: dbshell
dbshell: requirements
	python $(PROJECT_NAME)/manage.py dbshell

.PHONY: createsuperuser
createsuperuser: requirements
	python $(PROJECT_NAME)/manage.py createsuperuser
