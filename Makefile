VERSION=$(shell cat VERSION)

.PHONY: doc publish release release-check release-test release-deps test version

doc:
	./utils/copydoc.sh servers/ruby

# Run component test suites (install deps first or use nix develop).
test: doc
	cd servers/ruby && bundle exec rspec
	cd clients/ruby && bundle exec rspec
	cd clients/go && bundle exec rspec
	cd clients/js && npm test
	cd clients/php && vendor/bin/phpunit

release-deps:
	cd servers/ruby && bundle install
	cd clients/ruby && bundle install
	cd clients/go && bundle install
	cd clients/js && npm ci --no-audit --no-fund
	cd clients/php && composer install --no-interaction --prefer-dist

release-check:
	ruby utils/release/cli.rb check

release-test:
	bundle exec rspec utils/release/spec

release:
	bash utils/release/build.sh

publish:
	@echo 'Publish through the release GitHub Actions workflow; see doc/agent-instructions/releases.md.' >&2
	@exit 1

version:
	@echo "$(VERSION)" > VERSION
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" servers/ruby/lib/haveapi/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/ruby/lib/haveapi/client/version.rb
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/go/lib/haveapi/go_client/version.rb
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/js/package.json
	@node -e 'const fs = require("fs"); const p = "clients/js/package-lock.json"; const lock = JSON.parse(fs.readFileSync(p, "utf8")); lock.version = lock.packages[""].version = process.argv[1]; fs.writeFileSync(p, JSON.stringify(lock, null, "\t") + "\n");' "$(VERSION)"
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/src/haveapi/client.ts
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/dist/haveapi-client.js
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/php/composer.json
	@sed -ri "s/const VERSION = '[^']+'/const VERSION = '$(VERSION)'/" clients/php/src/Client.php
	@sed -ri "s/s.add_dependency 'haveapi-client', '~> [^']+'/s.add_dependency 'haveapi-client', '~> $(VERSION)'/" servers/ruby/haveapi.gemspec
	@sed -ri "s/spec.add_dependency 'haveapi-client', '~> [^']+'/spec.add_dependency 'haveapi-client', '~> $(VERSION)'/" clients/go/haveapi-go-client.gemspec
	@sed -ri "s/gem 'haveapi', '~> [^']+'/gem 'haveapi', '~> $(VERSION)'/" examples/servers/ruby/activerecord_auth/Gemfile
