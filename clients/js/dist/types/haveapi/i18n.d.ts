import type { HeaderMap, Language, Values } from './types';
export declare const I18n: {
    DEFAULT_LOCALE: string;
    DEFAULT_LANGUAGE_HEADER: string;
    translate: (language: Language | undefined, key: string, values?: Values) => string;
    requestHeaders: (language: Language | undefined, languageHeader?: string) => HeaderMap;
    localeFor: (language: Language | undefined) => string;
    assertHeaderName: (name: unknown) => void;
    assertHeaderValue: (value: unknown) => void;
    lookup: (locale: string, key: string) => string | null;
    parseAcceptLanguage: (header: string) => string[];
    normalizeLocale: (tag: string) => string | null;
};
