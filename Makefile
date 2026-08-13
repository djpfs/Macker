#===----------------------------------------------------------------------===//
# macker — build, test, and packaging targets.
#===----------------------------------------------------------------------===//

SWIFT      ?= swift
BUILD_DIR  ?= .build
BIN        := $(BUILD_DIR)/debug/macker
CONTAINER_VERSION := 1.2.2

.PHONY: all build test run clean release install guest-agent lint

all: build

## Build the debug binary (GUI + CLI dual mode).
build:
	$(SWIFT) build

## Run the test suite (requires full Xcode — XCTest is not in CommandLineTools).
test:
	$(SWIFT) test

## Run the CLI in headless mode (e.g. `make run -- docker ps`).
run: build
	$(BIN) $(ARGS)

## Build the release binary.
release:
	$(SWIFT) build -c release

## Install the binary to /usr/local/bin (symlinkable as `docker`).
install: build
	install -d /usr/local/bin
	install -m 0755 $(BIN) /usr/local/bin/macker
	@echo "Installed /usr/local/bin/macker"
	@echo "Optional aliases:"
	@echo "  ln -s /usr/local/bin/macker /usr/local/bin/docker"
	@echo "  ln -s /usr/local/bin/macker /usr/local/bin/docker-compose"

## Cross-compile the hot-reload guest agent (needs aarch64 Linux toolchain).
guest-agent:
	./Scripts/build-guest-agent.sh

## Remove build artifacts.
clean:
	rm -rf $(BUILD_DIR)

## Print the pinned apple/container version.
version:
	@echo "apple/container protocol pinned to $(CONTAINER_VERSION)"

## Lint (swift-format if available).
lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format lint -r Sources Tests; \
	else \
		echo "swift-format not found; skipping lint"; \
	fi
