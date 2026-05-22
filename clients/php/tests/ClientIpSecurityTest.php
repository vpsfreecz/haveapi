<?php

use PHPUnit\Framework\TestCase;

final class ClientIpSecurityTest extends TestCase
{
    private $originalServer;

    protected function setUp(): void
    {
        $this->originalServer = $_SERVER;
    }

    protected function tearDown(): void
    {
        $_SERVER = $this->originalServer;
    }

    public function testClientIpHonorsForwardedForHeader(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = '198.51.100.9, 203.0.113.77';
        $_SERVER['HTTP_CLIENT_IP'] = '203.0.113.88';
        $_SERVER['REMOTE_ADDR'] = '10.0.0.5';

        $client = new \HaveAPI\Client('https://api.example');
        $request = $client->getRequest('get', 'https://api.example/v1/audit');

        $this->assertSame('203.0.113.77', $client->getClientIp());
        $this->assertSame('203.0.113.77', $request->headers['Client-IP']);
    }

    public function testClientIpFallsBackToRemoteAddress(): void
    {
        $_SERVER['REMOTE_ADDR'] = '10.0.0.5';

        $client = new \HaveAPI\Client('https://api.example');
        $request = $client->getRequest('get', 'https://api.example/v1/audit');

        $this->assertSame('10.0.0.5', $client->getClientIp());
        $this->assertSame('10.0.0.5', $request->headers['Client-IP']);
    }

    public function testClientIpFallsBackToClientIpHeader(): void
    {
        $_SERVER['HTTP_CLIENT_IP'] = '203.0.113.88';

        $client = new \HaveAPI\Client('https://api.example');
        $request = $client->getRequest('get', 'https://api.example/v1/audit');

        $this->assertSame('203.0.113.88', $client->getClientIp());
        $this->assertSame('203.0.113.88', $request->headers['Client-IP']);
    }

    public function testInvalidForwardedAddressFallsBackToRemoteAddress(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = "203.0.113.77\r\nX-Injected: yes";
        $_SERVER['REMOTE_ADDR'] = '10.0.0.5';

        $client = new \HaveAPI\Client('https://api.example');
        $request = $client->getRequest('get', 'https://api.example/v1/audit');

        $this->assertSame('10.0.0.5', $client->getClientIp());
        $this->assertSame('10.0.0.5', $request->headers['Client-IP']);
    }

    public function testInvalidClientIpValuesAreNotForwarded(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = "203.0.113.77\r\nX-Injected: yes";
        $_SERVER['REMOTE_ADDR'] = "10.0.0.5\r\nX-Injected-Header: yes";
        $_SERVER['HTTP_CLIENT_IP'] = "203.0.113.88\r\nX-Injected: yes";

        $client = new \HaveAPI\Client('https://api.example');
        $request = $client->getRequest('get', 'https://api.example/v1/audit');

        $this->assertFalse($client->getClientIp());
        $this->assertArrayNotHasKey('Client-IP', $request->headers);
    }

    public function testOAuth2HttpClientHonorsForwardedForHeader(): void
    {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = '198.51.100.9, 203.0.113.77';
        $_SERVER['HTTP_CLIENT_IP'] = '203.0.113.88';
        $_SERVER['REMOTE_ADDR'] = '10.0.0.5';

        $auth = new \HaveAPI\Client\Authentication\OAuth2(
            new \HaveAPI\Client('https://api.example'),
            $this->newOAuth2Description(),
            $this->newOAuth2Options()
        );

        $headers = $this->guzzleHeadersFrom(
            $this->genericProviderFrom($auth)->getHttpClient()
        );

        $this->assertSame('203.0.113.77', $headers['Client-IP']);
    }

    public function testOAuth2HttpClientUsesClientIpHeaderFallback(): void
    {
        $_SERVER['HTTP_CLIENT_IP'] = '203.0.113.88';

        $auth = new \HaveAPI\Client\Authentication\OAuth2(
            new \HaveAPI\Client('https://api.example'),
            $this->newOAuth2Description(),
            $this->newOAuth2Options()
        );

        $headers = $this->guzzleHeadersFrom(
            $this->genericProviderFrom($auth)->getHttpClient()
        );

        $this->assertSame('203.0.113.88', $headers['Client-IP']);
    }

    private function newOAuth2Description(): \stdClass
    {
        return (object) [
            'authorize_url' => 'https://api.example/_auth/oauth2/authorize',
            'token_url' => 'https://api.example/_auth/oauth2/token',
        ];
    }

    private function newOAuth2Options(): array
    {
        return [
            'client_id' => 'vuln67-client-id',
            'client_secret' => 'vuln67-client-secret',
            'redirect_uri' => 'https://client.example/callback',
            'scope' => [],
        ];
    }

    private function genericProviderFrom(
        \HaveAPI\Client\Authentication\OAuth2 $auth
    ): \League\OAuth2\Client\Provider\GenericProvider {
        $property = new ReflectionProperty(
            \HaveAPI\Client\Authentication\OAuth2::class,
            'genericProvider'
        );
        $property->setAccessible(true);

        return $property->getValue($auth);
    }

    private function guzzleHeadersFrom(\GuzzleHttp\Client $client): array
    {
        $property = new ReflectionProperty(\GuzzleHttp\Client::class, 'config');
        $property->setAccessible(true);

        return $property->getValue($client)['headers'];
    }
}
