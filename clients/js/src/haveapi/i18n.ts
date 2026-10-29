import type { HeaderMap, Language, Values } from "./types";

type Catalog = { [name: string]: string | Catalog };
// Rollup injects the unchanged generated catalog inside the UMD factory.
declare const I18nMessages: Record<string, Catalog>;

export const I18n = {
  DEFAULT_LOCALE: "en",
  DEFAULT_LANGUAGE_HEADER: "Accept-Language",

  translate: function (
    language: Language | undefined,
    key: string,
    values?: Values,
  ) {
    var message =
      this.lookup(this.localeFor(language), key) ||
      this.lookup(this.DEFAULT_LOCALE, key) ||
      key;

    values = values || {};

    for (var name in values) {
      if (!values.hasOwnProperty(name)) continue;

      message = message.replace(
        new RegExp("%\\{" + name + "\\}", "g"),
        String(values[name]),
      );
    }

    return message;
  },

  requestHeaders: function (
    language: Language | undefined,
    languageHeader?: string,
  ) {
    var ret: HeaderMap = {};

    if (language === undefined || language === null || String(language) === "")
      return ret;

    languageHeader = languageHeader || this.DEFAULT_LANGUAGE_HEADER;
    this.assertHeaderName(languageHeader);
    this.assertHeaderValue(language);

    ret[languageHeader] = String(language);
    return ret;
  },

  localeFor: function (language: Language | undefined) {
    if (language === undefined || language === null || String(language) === "")
      return this.DEFAULT_LOCALE;

    var tags = this.parseAcceptLanguage(String(language));

    for (var i = 0; i < tags.length; i++) {
      var locale = this.normalizeLocale(tags[i]);

      if (locale && I18nMessages.hasOwnProperty(locale)) return locale;
    }

    return this.DEFAULT_LOCALE;
  },

  assertHeaderName: function (name: unknown) {
    if (
      typeof name !== "string" ||
      !name.match(/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/)
    )
      throw new Error("Invalid language HTTP header name");
  },

  assertHeaderValue: function (value: unknown) {
    if (
      typeof value !== "string" &&
      typeof value !== "number" &&
      typeof value !== "boolean"
    )
      throw new Error("Invalid language HTTP header value");

    if (String(value).match(/[\x00\r\n]/))
      throw new Error("Invalid language HTTP header value");
  },

  lookup: function (locale: string, key: string): string | null {
    var data: string | Catalog | undefined = I18nMessages[locale];
    var parts = String(key)
      .replace(/^haveapi_client\./, "")
      .split(".");

    for (var i = 0; i < parts.length; i++) {
      if (!data || typeof data === "string" || !data.hasOwnProperty(parts[i]))
        return null;

      data = data[parts[i]];
    }

    return typeof data === "string" ? data : null;
  },

  parseAcceptLanguage: function (header: string): string[] {
    var ret: Array<[string, number]> = [];
    var parts = header.split(",");

    for (var i = 0; i < parts.length; i++) {
      var tokens = parts[i].split(";");
      var tag = tokens.shift()!.trim();
      var q = 1.0;

      for (var j = 0; j < tokens.length; j++) {
        var qTokens = tokens[j].split("=");

        if (qTokens[0].trim() == "q") q = parseFloat(qTokens[1]);
      }

      if (tag !== "" && q > 0) ret.push([tag, q]);
    }

    ret.sort(function (a, b) {
      return b[1] - a[1];
    });

    return ret.map(function (v) {
      return v[0];
    });
  },

  normalizeLocale: function (tag: string): string | null {
    var normalized = String(tag)
      .trim()
      .replace(/_/g, "-")
      .replace(/\..*$/, "")
      .toLowerCase();

    if (normalized === "") return null;

    return normalized.split("-", 1)[0];
  },
};
