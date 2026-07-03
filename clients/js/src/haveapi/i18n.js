var I18n = {
	DEFAULT_LOCALE: 'en',
	DEFAULT_LANGUAGE_HEADER: 'Accept-Language',

	translate: function(language, key, values) {
		var message = this.lookup(this.localeFor(language), key) ||
			this.lookup(this.DEFAULT_LOCALE, key) ||
			key;

		values = values || {};

		for (var name in values) {
			if (!values.hasOwnProperty(name))
				continue;

			message = message.replace(new RegExp('%\\{'+ name +'\\}', 'g'), String(values[name]));
		}

		return message;
	},

	requestHeaders: function(language, languageHeader) {
		var ret = {};

		if (language === undefined || language === null || String(language) === '')
			return ret;

		languageHeader = languageHeader || this.DEFAULT_LANGUAGE_HEADER;
		this.assertHeaderName(languageHeader);
		this.assertHeaderValue(language);

		ret[languageHeader] = String(language);
		return ret;
	},

	localeFor: function(language) {
		if (language === undefined || language === null || String(language) === '')
			return this.DEFAULT_LOCALE;

		var tags = this.parseAcceptLanguage(String(language));

		for (var i = 0; i < tags.length; i++) {
			var locale = this.normalizeLocale(tags[i]);

			if (locale && I18nMessages.hasOwnProperty(locale))
				return locale;
		}

		return this.DEFAULT_LOCALE;
	},

	assertHeaderName: function(name) {
		if (typeof name !== 'string' || !name.match(/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/))
			throw new Error('Invalid language HTTP header name');
	},

	assertHeaderValue: function(value) {
		if (typeof value !== 'string' && typeof value !== 'number' && typeof value !== 'boolean')
			throw new Error('Invalid language HTTP header value');

		if (String(value).match(/[\x00\r\n]/))
			throw new Error('Invalid language HTTP header value');
	},

	lookup: function(locale, key) {
		var data = I18nMessages[locale];
		var parts = String(key).replace(/^haveapi_client\./, '').split('.');

		for (var i = 0; i < parts.length; i++) {
			if (!data || !data.hasOwnProperty(parts[i]))
				return null;

			data = data[parts[i]];
		}

		return typeof data === 'string' ? data : null;
	},

	parseAcceptLanguage: function(header) {
		var ret = [];
		var parts = header.split(',');

		for (var i = 0; i < parts.length; i++) {
			var tokens = parts[i].split(';');
			var tag = tokens.shift().trim();
			var q = 1.0;

			for (var j = 0; j < tokens.length; j++) {
				var qTokens = tokens[j].split('=');

				if (qTokens[0].trim() == 'q')
					q = parseFloat(qTokens[1]);
			}

			if (tag !== '' && q > 0)
				ret.push([tag, q]);
		}

		ret.sort(function(a, b) {
			return b[1] - a[1];
		});

		return ret.map(function(v) {
			return v[0];
		});
	},

	normalizeLocale: function(tag) {
		var normalized = String(tag).trim().replace(/_/g, '-').replace(/\..*$/, '').toLowerCase();

		if (normalized === '')
			return null;

		return normalized.split('-', 1)[0];
	}
};
