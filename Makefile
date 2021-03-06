.PHONY: help
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

GLEAN_PYENV := $(shell python3 -c "import sys; print('glean-core/python/.venv' + '.'.join(str(x) for x in sys.version_info[:2]))")
GLEAN_PYDEPS := ${GLEAN_PYDEPS}

# Setup environments

python-setup: $(GLEAN_PYENV)/bin/python3 ## Setup a Python virtual environment
	@:

$(GLEAN_PYENV)/bin/python3:
	python3 -m venv $(GLEAN_PYENV)
	$(GLEAN_PYENV)/bin/pip install --upgrade pip
	$(GLEAN_PYENV)/bin/pip install -r glean-core/python/requirements_dev.txt
	bash -c "if [ \"$(GLEAN_PYDEPS)\" == \"min\" ]; then \
		$(GLEAN_PYENV)/bin/pip install requirements-builder; \
		$(GLEAN_PYENV)/bin/requirements-builder --level=min glean-core/python/setup.py > min_requirements.txt; \
		$(GLEAN_PYENV)/bin/pip install -r min_requirements.txt; \
	fi"
	# black isn't installable on Python 3.5, but we can do without it
	$(GLEAN_PYENV)/bin/pip install black || true

# All builds

build: build-rust

build-rust: ## Build all Rust code
	cargo build --all

build-kotlin: ## Build all Kotlin code
	./gradlew build -x test

build-swift: ## Build all Swift code
	bin/run-ios-build.sh

build-apk: ## Build an apk of the Glean sample app
	./gradlew glean-core:build
	./gradlew glean-sample-app:build

build-python: python-setup build-rust ## Build the Python bindings
	$(GLEAN_PYENV)/bin/python3 glean-core/python/setup.py install

.PHONY: build build-rust build-kotlin build-swift build-apk

# All tests

test: test-rust

test-rust: ## Run Rust tests for glean-core and glean-ffi
	cargo test --all

test-rust-with-logs: ## Run all Rust tests with debug logging and single-threaded
	RUST_LOG=glean_core=debug cargo test --all -- --nocapture --test-threads=1

test-kotlin: ## Run all Kotlin tests
	./gradlew :glean:testDebugUnitTest

test-swift: ## Run all Swift tests
	bin/run-ios-tests.sh

test-ios-sample: ## Run the iOS UI tests on the sample app
	bin/run-ios-sample-app-test.sh

test-python: build-python ## Run all Python tests
	$(GLEAN_PYENV)/bin/py.test glean-core/python/tests $(PYTEST_ARGS)

.PHONY: test test-rust test-rust-with-logs test-kotlin test-swift test-ios-sample

# Benchmarks

bench-rust: ## Run Rust benchmarks
	cargo bench -p benchmark

.PHONY: bench-rust

# Linting

lint: clippy

clippy: ## Run cargo-clippy to lint Rust code
	cargo clippy --all --all-targets --all-features -- -D warnings

ktlint: ## Run ktlint to lint Kotlin code
	./gradlew ktlint detekt

swiftlint: ## Run swiftlint to lint Swift code
	swiftlint --strict

yamllint: ## Run yamllint to lint YAML files
	yamllint glean-core .circleci

shellcheck: ## Run shellcheck against important shell scripts
	shellcheck glean-core/ios/sdk_generator.sh

pythonlint: python-setup ## Run flake8 and black to lint Python code
	$(GLEAN_PYENV)/bin/python3 -m flake8 glean-core/python/glean glean-core/python/tests
	$(GLEAN_PYENV)/bin/python3 -m black --check --exclude \(.venv\*\)\|\(.eggs\) glean-core/python
	$(GLEAN_PYENV)/bin/python3 -m mypy glean-core/python/glean

.PHONY: lint clippy ktlint swiftlint yamllint

# Formatting

fmt: rustfmt

rustfmt: ## Format all Rust code
	cargo fmt --all

swiftfmt: ## Format all Swift code
	swiftformat glean-core/ios samples/ios --swiftversion 5 --verbose

pythonfmt: python-setup ## Run black to format Python code
	$(GLEAN_PYENV)/bin/python3 -m black glean-core/python/glean glean-core/python/tests

.PHONY: fmt rustfmt swiftfmt

# Docs

docs: rust-docs kotlin-docs ## Build the Rust and Kotlin API documentation

rust-docs: ## Build the Rust documentation
	bin/build-rust-docs.sh

kotlin-docs: ## Build the Kotlin documentation
	./gradlew docs

swift-docs: ## Build the Swift documentation
	bin/build-swift-docs.sh

python-docs: build-python ## Build the Python documentation
	$(GLEAN_PYENV)/bin/python3 -m pdoc --html glean --force -o build/docs/python --config show_type_annotations=True

.PHONY: docs rust-docs kotlin-docs swift-docs

linkcheck: docs ## Run linkchecker on the generated docs
	# Requires https://wummel.github.io/linkchecker/
	linkchecker \
		--ignore-url javadoc \
		--ignore-url swift \
		--ignore-url python \
		--ignore-url docs/glean_core \
		--ignore-url ErrorKind \
		--ignore-url std.struct.Error \
		build/docs
.PHONY: linkcheck

spellcheck: ## Spellcheck the docs
	# Requires http://aspell.net/
	bin/spellcheck.sh

# Utilities

android-emulator: ## Start the Android emulator with a predefined image
	$(ANDROID_HOME)/emulator/emulator -avd Nexus_5X_API_P -netdelay none -netspeed full
.PHONY: android-emulator

cbindgen: ## Regenerate the FFI header file
	RUSTUP_TOOLCHAIN=nightly \
	cbindgen glean-core/ffi --lockfile Cargo.lock -o glean-core/ffi/glean.h
	cp glean-core/ffi/glean.h glean-core/ios/Glean/GleanFfi.h
.PHONY: cbindgen

rust-coverage: export CARGO_INCREMENTAL=0
rust-coverage: export RUSTFLAGS=-Zprofile -Ccodegen-units=1 -Cinline-threshold=0 -Clink-dead-code -Coverflow-checks=off -Zno-landing-pads
rust-coverage: export RUSTUP_TOOLCHAIN=nightly
rust-coverage: ## Generate code coverage information for Rust code
	# Expects a Rust nightly toolchain to be available.
	# Expects grcov and genhtml to be available in $PATH.
	cargo build --verbose
	cargo test --verbose
	zip -0 ccov.zip `find . \( -name "glean*.gc*" \) -print`
	grcov ccov.zip -s . -t lcov --llvm --branch --ignore-not-existing --ignore "/*" --ignore "glean-core/ffi/*" -o lcov.info
	genhtml -o report/ --show-details --highlight --ignore-errors source --legend lcov.info
.PHONY: rust-coverage

python-coverage: build-python ## Generate a code coverage report for Python
	$(GLEAN_PYENV)/bin/python3 -m coverage run --parallel-mode -m pytest
	$(GLEAN_PYENV)/bin/python3 -m coverage combine
	$(GLEAN_PYENV)/bin/python3 -m coverage html
.PHONY: python-coverage
