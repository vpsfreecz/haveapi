<?php

use PHPUnit\Framework\TestCase;

final class TokenAuthenticationI18nTest extends TestCase
{
    public function testMissingMultistepCallbackIsLocalized(): void
    {
        $auth = $this->newTokenAuth([]);

        $this->expectException(\BadFunctionCallException::class);
        $this->expectExceptionMessage('přidejte callback pro zpracování vícefázového ověření');

        $auth->run();
    }

    public function testInvalidMultistepCallbackReturnIsLocalized(): void
    {
        $auth = $this->newTokenAuth([
            'callback' => fn() => 'continue',
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage("callback musí vrátit pole nebo 'stop'");

        $auth->run();
    }

    private function newTokenAuth(array $opts): TokenAuthenticationI18nProbe
    {
        return new TokenAuthenticationI18nProbe(
            new \HaveAPI\Client(
                'https://api.example',
                null,
                'haveapi-client-php-test',
                ['language' => 'cs']
            ),
            (object) [],
            $opts
        );
    }
}

final class TokenAuthenticationI18nProbe extends \HaveAPI\Client\Authentication\Token
{
    public function run(): void
    {
        $this->runAuthentication('request', []);
    }

    protected function setup() {}

    protected function authenticationStep($action, $input)
    {
        return ['continue', 'verify', 'intermediate-token'];
    }

    protected function getCustomActionCredentials($action)
    {
        return [];
    }
}
