<?php

namespace HaveAPI\Client;

final class I18n
{
    public const DEFAULT_LOCALE = 'en';
    public const DEFAULT_LANGUAGE_HEADER = 'Accept-Language';

    public static function translate($language, string $key, array $values = []): string
    {
        $message = self::lookup(self::localeFor($language), $key)
            ?? self::lookup(self::DEFAULT_LOCALE, $key)
            ?? $key;

        foreach ($values as $name => $value) {
            $message = str_replace('%{' . $name . '}', (string) $value, $message);
        }

        return $message;
    }

    public static function requestHeaders($language, string $languageHeader = self::DEFAULT_LANGUAGE_HEADER): array
    {
        if ($language === null || (string) $language === '') {
            return [];
        }

        self::assertHeaderName($languageHeader);
        self::assertHeaderValue($language);

        return [$languageHeader => (string) $language];
    }

    public static function localeFor($language): string
    {
        if ($language === null || (string) $language === '') {
            return self::DEFAULT_LOCALE;
        }

        foreach (self::parseAcceptLanguage((string) $language) as $tag) {
            $locale = self::normalizeLocale($tag);

            if ($locale !== null && isset(I18nMessages::MESSAGES[$locale])) {
                return $locale;
            }
        }

        return self::DEFAULT_LOCALE;
    }

    public static function assertHeaderName($name): void
    {
        if (!is_string($name) || preg_match('/\A[!#$%&\'*+.^_`|~0-9A-Za-z-]+\z/', $name) !== 1) {
            throw new \InvalidArgumentException('Invalid language HTTP header name');
        }
    }

    public static function assertHeaderValue($value): void
    {
        if (!is_scalar($value) || preg_match('/[\x00\r\n]/', (string) $value) !== 0) {
            throw new \InvalidArgumentException('Invalid language HTTP header value');
        }
    }

    private static function lookup(string $locale, string $key): ?string
    {
        $parts = explode('.', preg_replace('/\Ahaveapi_client\./', '', $key));
        $data = I18nMessages::MESSAGES[$locale] ?? null;

        foreach ($parts as $part) {
            if (!is_array($data) || !array_key_exists($part, $data)) {
                return null;
            }

            $data = $data[$part];
        }

        return is_string($data) ? $data : null;
    }

    private static function parseAcceptLanguage(string $header): array
    {
        $ret = [];

        foreach (explode(',', $header) as $part) {
            $tokens = array_map('trim', explode(';', $part));
            $tag = array_shift($tokens);
            $q = 1.0;

            foreach ($tokens as $token) {
                [$name, $value] = array_pad(array_map('trim', explode('=', $token, 2)), 2, null);

                if ($name === 'q' && $value !== null) {
                    $q = (float) $value;
                }
            }

            if ($tag !== '' && $q > 0) {
                $ret[] = [$tag, $q];
            }
        }

        usort($ret, fn($a, $b) => $b[1] <=> $a[1]);

        return array_map(fn($item) => $item[0], $ret);
    }

    private static function normalizeLocale(string $tag): ?string
    {
        $normalized = strtolower(str_replace('_', '-', preg_replace('/\..*\z/', '', trim($tag))));

        if ($normalized === '') {
            return null;
        }

        return explode('-', $normalized, 2)[0];
    }
}
