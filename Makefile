VERSION=$(shell cat VERSION)

.PHONY: publish release version

release:
	mkdir -p dist
	
	cd servers/ruby && rake build
	mv servers/ruby/pkg/haveapi-$(VERSION).gem dist/
	
	cd clients/ruby && rake build
	mv clients/ruby/pkg/haveapi-client-$(VERSION).gem dist/
	
	cd clients/js && ./node_modules/.bin/gulp
	cp clients/js/dist/haveapi-client.js dist/

publish:
	gem push dist/haveapi-$(VERSION).gem
	gem push dist/haveapi-client-$(VERSION).gem
	
	mkdir -p tmp/haveapi-client-js
	cd clients/js && cp -p --parents $(shell cd clients/js && git ls-files) ../../tmp/haveapi-client-js/
	cd tmp/haveapi-client-js && npm publish
	rm -rf tmp/haveapi-client-js

version:
	@echo "$(VERSION)" > VERSION
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" servers/ruby/lib/haveapi/version.rb
	@sed -ri "s/version: \"[^\"]+\"/version: \"$(VERSION)\"/" servers/elixir/mix.exs
	@sed -ri "s/ VERSION = '[^']+'/ VERSION = '$(VERSION)'/" clients/ruby/lib/haveapi/client/version.rb
	@sed -ri "s/version: \"[^\"]+\"/version: \"$(VERSION)\"/" clients/elixir/mix.exs
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/js/package.json
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/src/haveapi/client.js
	@sed -ri "s/Client\.Version = '[^']+'/Client.Version = '$(VERSION)'/" clients/js/dist/haveapi-client.js
	@sed -ri "s/\"version\": \"[^\"]+\"/\"version\": \"$(VERSION)\"/" clients/php/composer.json
	@sed -ri "s/const VERSION = '[^']+'/const VERSION = '$(VERSION)'/" clients/php/src/Client.php

