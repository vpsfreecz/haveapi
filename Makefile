.PHONY: version

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

