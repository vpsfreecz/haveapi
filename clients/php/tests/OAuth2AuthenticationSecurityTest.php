<?php

use PHPUnit\Framework\TestCase;

final class OAuth2AuthenticationSecurityTest extends TestCase
{
    private $originalGet;
    private $originalSession;
    private $hadSession;

    protected function setUp(): void
    {
        $this->originalGet = $_GET;
        $this->hadSession = isset($_SESSION);
        $this->originalSession = $this->hadSession ? $_SESSION : null;
    }

    protected function tearDown(): void
    {
        $_GET = $this->originalGet;

        if ($this->hadSession) {
            $_SESSION = $this->originalSession;
        } else {
            unset($_SESSION);
        }
    }

    public function testRejectsEmptyCallbackStateWithoutSessionState(): void
    {
        $auth = $this->newOAuth2AuthWithProvider($provider, ['language' => 'cs']);
        $_SESSION = [];
        $_GET = [
            'state' => '',
            'code' => 'attacker-supplied-code',
        ];

        try {
            $auth->requestAccessToken();
            $this->fail('Expected AuthenticationFailed');
        } catch (\HaveAPI\Client\Exception\AuthenticationFailed $e) {
            $this->assertSame('Neplatný OAuth2 state', $e->getMessage());
        }

        $this->assertNull($provider->grant);
        $this->assertSame('not-called', $provider->pkceCode);
    }

    public function testRequiresStoredPkceVerifier(): void
    {
        $auth = $this->newOAuth2AuthWithProvider($provider, ['language' => 'cs']);
        $_SESSION = [
            'oauth2state' => 'expected-state',
        ];
        $_GET = [
            'state' => 'expected-state',
            'code' => 'authorization-code',
        ];

        try {
            $auth->requestAccessToken();
            $this->fail('Expected AuthenticationFailed');
        } catch (\HaveAPI\Client\Exception\AuthenticationFailed $e) {
            $this->assertSame('Neplatný OAuth2 PKCE verifier', $e->getMessage());
        }

        $this->assertNull($provider->grant);
        $this->assertSame('not-called', $provider->pkceCode);
        $this->assertArrayNotHasKey('oauth2state', $_SESSION);
    }

    public function testAcceptsMatchingStateAndClearsSessionData(): void
    {
        $auth = $this->newOAuth2AuthWithProvider($provider);
        $_SESSION = [
            'oauth2state' => 'expected-state',
            'oauth2pkceCode' => 'stored-pkce-verifier',
        ];
        $_GET = [
            'state' => 'expected-state',
            'code' => 'authorization-code',
        ];

        $auth->requestAccessToken();

        $this->assertSame('authorization_code', $provider->grant);
        $this->assertSame('authorization-code', $provider->params['code']);
        $this->assertSame('stored-pkce-verifier', $provider->pkceCode);
        $this->assertArrayNotHasKey('oauth2state', $_SESSION);
        $this->assertArrayNotHasKey('oauth2pkceCode', $_SESSION);
    }

    private function newOAuth2AuthWithProvider(
        &$provider,
        array $clientOptions = []
    ): \HaveAPI\Client\Authentication\OAuth2 {
        $auth = new \HaveAPI\Client\Authentication\OAuth2(
            new \HaveAPI\Client(
                'https://api.example',
                null,
                'haveapi-client-php-test',
                $clientOptions
            ),
            (object) [],
            []
        );
        $provider = new OAuth2AuthenticationSecurityFakeProvider();

        $property = new ReflectionProperty(
            \HaveAPI\Client\Authentication\OAuth2::class,
            'genericProvider'
        );
        $property->setAccessible(true);
        $property->setValue($auth, $provider);

        return $auth;
    }
}

final class OAuth2AuthenticationSecurityFakeProvider
{
    public $pkceCode = 'not-called';
    public $grant = null;
    public $params = null;

    public function setPkceCode($code): void
    {
        $this->pkceCode = $code;
    }

    public function getAccessToken($grant, $params): \League\OAuth2\Client\Token\AccessToken
    {
        $this->grant = $grant;
        $this->params = $params;

        return new \League\OAuth2\Client\Token\AccessToken([
            'access_token' => 'test-access-token',
        ]);
    }
}
