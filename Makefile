SHELL := /bin/zsh
.PHONY: build run test install icon
build:
	./scripts/build-app.sh
run:
	./scripts/build-and-launch.sh
test:
	./scripts/test.sh
install: build
	./scripts/install-app.sh
icon:
	./scripts/make-icon.sh
