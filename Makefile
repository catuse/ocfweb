BIN := venv/bin
PYTHON := $(BIN)/python
SHELL := /bin/bash
RANDOM_PORT := $(shell expr $$(( 8000 + (`id -u` % 1000) )))
DOCKER_REPO ?=
DOCKER_REVISION ?= testing-$(USER)
DOCKER_TAG_BASE = ocfweb-base-$(USER)
DOCKER_TAG_WEB = $(DOCKER_REPO)ocfweb-web:$(DOCKER_REVISION)
DOCKER_TAG_WORKER = $(DOCKER_REPO)ocfweb-worker:$(DOCKER_REVISION)
DOCKER_TAG_STATIC = $(DOCKER_REPO)ocfweb-static:$(DOCKER_REVISION)

.PHONY: test
test: venv
	$(BIN)/coverage run -m py.test -v tests/
	$(BIN)/coverage report
	$(BIN)/pre-commit run --all-files

.PHONY: Dockerfile.%
Dockerfile.%: Dockerfile.%.in
	sed 's/{tag}/$(DOCKER_TAG_BASE)/g' "$<" > "$@"

.PHONY: cook-image
cook-image: Dockerfile.web Dockerfile.worker Dockerfile.static
	docker build --no-cache -t $(DOCKER_TAG_BASE) .
	docker build --no-cache -t $(DOCKER_TAG_WEB) -f Dockerfile.web .
	docker build --no-cache -t $(DOCKER_TAG_WORKER) -f Dockerfile.worker .
	docker build --no-cache -t $(DOCKER_TAG_STATIC) -f Dockerfile.static .

.PHONY: push-image
push-image:
	docker push $(DOCKER_TAG_WEB)
	docker push $(DOCKER_TAG_WORKER)
	docker push $(DOCKER_TAG_STATIC)

# first set COVERALLS_REPO_TOKEN=<repo token> environment variable
.PHONY: coveralls
coveralls: venv test
	$(BIN)/coveralls

.PHONY: dev
dev: venv ocfweb/static/scss/site.scss.css
	@echo -e "\e[1m\e[93mRunning on http://$(shell hostname -f ):$(RANDOM_PORT)/\e[0m"
	$(PYTHON) ./manage.py runserver 0.0.0.0:$(RANDOM_PORT)

venv: requirements.txt requirements-dev.txt
	python ./vendor/venv-update venv= venv -ppython3 install= -r requirements.txt -r requirements-dev.txt

.PHONY: clean
clean:
	rm -rf *.egg-info venv

# closer to prod
.PHONY: gunicorn
gunicorn: venv
	@echo "Running on port $(RANDOM_PORT)"
	$(BIN)/gunicorn -b 0.0.0.0:$(RANDOM_PORT) ocfweb.wsgi

# phony because it depends on other files, too many to express
.PHONY: ocfweb/static/scss/site.scss.css
ocfweb/static/scss/site.scss.css: ocfweb/static/scss/site.scss venv
	$(BIN)/sassc "$<" "$@"

.PHONY: watch-scss
watch-scss: venv
	while :; do \
		make ocfweb/static/scss/site.scss.css; \
		find ocfweb/static -type f -name '*.scss' | \
			inotifywait --fromfile - -e modify; \
	done

.PHONY: update-requirements
update-requirements:
	$(eval TMP := $(shell mktemp -d))
	python ./vendor/venv-update venv= $(TMP) -ppython3 install= -r requirements-minimal.txt
	. $(TMP)/bin/activate && \
		pip freeze | sort | grep -vE '^(wheel|venv-update)==' | sed 's/^ocflib==.*/ocflib/' > requirements.txt
	rm -rf $(TMP)
