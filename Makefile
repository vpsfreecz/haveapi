VERSION=$(shell cat VERSION)
BENCHMARK_DOCUMENTATION_RUBY ?= bundle exec ruby
RUST_ENV=env -u RUBYOPT -u RUBYLIB -u BUNDLE_BIN_PATH -u BUNDLE_LOCKFILE -u BUNDLE_PATH -u BUNDLE_FROZEN -u BUNDLER_SETUP GEM_HOME="$(CURDIR)/clients/rust/.gems" GEM_PATH="$(CURDIR)/clients/rust/.gems:$$(ruby -e 'puts Gem.default_dir')" BUNDLE_GEMFILE="$(CURDIR)/clients/rust/Gemfile"

.PHONY: benchmark-documentation performance performance-compare test-performance doc publish release release-check release-test release-deps release-rust test test-documentation test-documentation-generated test-documentation-assets test-documentation-python test-rust test-rust-unit test-schema test-go-cli test-typescript version

doc:
	./utils/copydoc.sh servers/ruby

# Run component test suites (install deps first or use nix develop).
test: doc
	cd clients/js && npm run build
	cd servers/ruby && bundle exec rspec
	cd clients/ruby && bundle exec rspec
	cd clients/go && bundle exec rspec
	$(MAKE) test-typescript
	$(MAKE) test-documentation-generated
	cd clients/js && npm test
	cd clients/php && vendor/bin/phpunit
	clients/python/utils/check.sh
	cd clients/python && uv run --locked pytest tests/integration
	$(MAKE) test-rust
	$(MAKE) test-documentation-assets
	$(MAKE) test-documentation-python

test-documentation: doc
	cd clients/js && npm run build
	cd servers/ruby && bundle exec rspec spec/client_examples spec/documentation
	$(MAKE) test-documentation-assets

# Prepared server bundle; optional generator sources are selected explicitly here.
test-documentation-generated: doc
	cd servers/ruby && bundle exec ruby -I../../clients/ruby/lib -I../../clients/typescript/lib -S rspec spec/client_examples/typescript_profiles_spec.rb spec/client_examples/ts_generated_client_spec.rb spec/client_examples/profile_mount_spec.rb

test-schema:
	bundle exec ruby -Iclients/ruby/lib -S rspec clients/ruby/spec/schema_*_spec.rb

test-go-cli:
	cd clients/go && bundle exec ruby -I../ruby/lib -Ilib -S rspec spec/unit

# Opt-in; stdout contains only the benchmark JSON. Prepare the server bundle first.
benchmark-documentation:
	@$(MAKE) --no-print-directory --silent doc
	@cd servers/ruby && $(BENCHMARK_DOCUMENTATION_RUBY) benchmarks/documentation.rb $(BENCHMARK_DOCUMENTATION_ARGS)

# Run in the prepared unbundled server environment; see doc/performance.md.
performance:
	ruby servers/ruby/benchmarks/endpoints.rb run $(PERFORMANCE_ARGS)

performance-compare:
	ruby servers/ruby/benchmarks/endpoints.rb compare $(PERFORMANCE_ARGS)

test-performance: doc
	cd servers/ruby && bundle exec rspec spec/performance

test-documentation-assets:
	node servers/ruby/spec/client_examples/assets/highlighter_test.cjs
	node servers/ruby/spec/client_examples/assets/tabs_test.cjs

# Requires the locked Python environment prepared by release-deps.
test-documentation-python:
	cd servers/ruby && bundle exec rspec test_support/dynamic_protocol_spec.rb test_support/dynamic_python_login_spec.rb

test-rust-unit:
	cd clients/rust && $(RUST_ENV) bundle exec rspec spec/unit

# Source-distributed generator: the root bundle supplies its development tools.
test-typescript:
	bundle exec ruby -Iclients/ruby/lib -Iclients/typescript/lib -S rspec clients/typescript/spec/unit

# Run in nix develop .#client-rust after the generator unit checks.
test-rust: test-rust-unit
	cd clients/rust/runtime && cargo test --locked
	cd clients/rust/runtime && cargo test --locked --features blocking
	$(RUST_ENV) HAVEAPI_RUST_INTEGRATION=1 ruby clients/rust/spec/integration/run.rb

release-deps:
	cd servers/ruby && bundle install
	cd clients/ruby && bundle install
	cd clients/go && bundle install
	cd clients/rust && $(RUST_ENV) gem install --no-document bundler
	cd clients/rust && $(RUST_ENV) bundle install
	cd clients/typescript && bundle install
	cd clients/js && npm install --no-audit --no-fund
	cd utils/highlight && npm ci --ignore-scripts --no-audit --no-fund
	cd utils/highlight && npm run check
	cd clients/php && composer install --no-interaction --prefer-dist
	cd clients/python && uv sync

release-check:
	ruby utils/release/cli.rb check
	ruby utils/release/cli.rb check-inputs

release-test:
	bundle exec rspec utils/release/spec
	python utils/release/spec/python_artifacts_test.py

release:
	bash utils/release/build.sh

release-rust:
	cd clients/rust && $(RUST_ENV) bundle exec rake build

publish:
	@echo 'Publish through the release GitHub Actions workflow; see doc/agent-instructions/releases.md.' >&2
	@exit 1

version:
	@ruby utils/release/cli.rb check-inputs
	@echo "$(VERSION)" > VERSION
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" servers/ruby/lib/haveapi/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/ruby/lib/haveapi/client/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/go/lib/haveapi/go_client/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/rust/lib/haveapi/rust_client/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/typescript/lib/haveapi/typescript_client/version.rb
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/js/package.json
	@node -e 'const fs = require("fs"); const p = "clients/js/package-lock.json"; const lock = JSON.parse(fs.readFileSync(p, "utf8")); lock.version = lock.packages[""].version = process.argv[1]; fs.writeFileSync(p, JSON.stringify(lock, null, "\t") + "\n");' "$(VERSION)"
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/src/haveapi/client.ts
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/dist/haveapi-client.js
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/php/composer.json
	@sed -ri "s/const VERSION = '[^']+'/const VERSION = '$(VERSION)'/" clients/php/src/Client.php
	@sed -ri 's/^version = "[^"]+"/version = "$(VERSION)"/' clients/python/pyproject.toml
	@cd clients/python && uv lock
	@sed -ri "s/s.add_dependency 'haveapi-client', '~> [^']+'/s.add_dependency 'haveapi-client', '~> $(VERSION)'/" servers/ruby/haveapi.gemspec
	@sed -ri "s/spec.add_dependency 'haveapi-client', '~> [^']+'/spec.add_dependency 'haveapi-client', '~> $(VERSION)'/" clients/rust/haveapi-rust-client.gemspec
	@sed -ri "s/spec.add_dependency 'haveapi-client', '~> [^']+'/spec.add_dependency 'haveapi-client', '~> $(VERSION)'/" clients/go/haveapi-go-client.gemspec
	@sed -ri "s/spec.add_dependency 'haveapi-client', '~> [^']+'/spec.add_dependency 'haveapi-client', '~> $(VERSION)'/" clients/typescript/haveapi-typescript-client.gemspec
	@sed -ri "s/gem 'haveapi', '~> [^']+'/gem 'haveapi', '~> $(VERSION)'/" examples/servers/ruby/activerecord_auth/Gemfile
	@$(RUST_ENV) bundle lock --local
