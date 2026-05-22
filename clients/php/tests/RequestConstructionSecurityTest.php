<?php

use PHPUnit\Framework\TestCase;

final class RequestConstructionSecurityTest extends TestCase
{
    public function testQueryParameterNamesAreEncoded(): void
    {
        $client = new RequestConstructionSecurityTestClient();
        $request = new RequestConstructionSecurityTestRequest('https://api.example/v1/users');
        $action = new RequestConstructionSecurityTestAction('get');

        $client->sendForTest($request, $action, [
            'user' => [
                'name]=alice&_meta[includes' => 'group__secret',
            ],
        ]);

        $this->assertStringContainsString(
            'user%5Bname%5D%3Dalice%26_meta%5Bincludes%5D=group__secret',
            $request->uri
        );
        $this->assertStringNotContainsString('&_meta[includes]', $request->uri);

        parse_str(parse_url($request->uri, PHP_URL_QUERY), $parsed);

        $this->assertArrayNotHasKey('_meta', $parsed);
    }

    public function testOAuth2RevocationParameterNamesAreEncoded(): void
    {
        $client = new RequestConstructionSecurityOAuthClient();
        $description = (object) [
            'revoke_url' => 'https://api.example/_auth/oauth2/revoke',
        ];
        $auth = new \HaveAPI\Client\Authentication\OAuth2($client, $description, []);

        $auth->revokeToken([
            'token=abc&token_type_hint' => 'refresh+token%value',
        ]);

        $this->assertSame(
            'token%3Dabc%26token_type_hint=refresh%2Btoken%25value',
            $client->lastRequest->bodyValue
        );

        parse_str($client->lastRequest->bodyValue, $parsed);

        $this->assertArrayNotHasKey('token', $parsed);
        $this->assertArrayNotHasKey('token_type_hint', $parsed);
        $this->assertSame(
            'refresh+token%value',
            $parsed['token=abc&token_type_hint']
        );
    }
}

final class RequestConstructionSecurityTestClient extends \HaveAPI\Client
{
    public function sendForTest($request, $action = null, $params = [])
    {
        $queryParams = new ReflectionProperty(\HaveAPI\Client::class, 'queryParams');
        $queryParams->setAccessible(true);
        $queryParams->setValue($this, []);

        return $this->sendRequest($request, $action, $params);
    }
}

final class RequestConstructionSecurityTestRequest
{
    public $uri;
    public $bodyValue;
    public $sent = false;

    public function __construct($uri)
    {
        $this->uri = $uri;
    }

    public function sendsForm()
    {
        return $this;
    }

    public function body($body)
    {
        $this->bodyValue = $body;
        return $this;
    }

    public function send()
    {
        $this->sent = true;
        return $this;
    }
}

final class RequestConstructionSecurityOAuthClient extends \HaveAPI\Client
{
    public $lastRequest;

    public function getRequest($method, $url)
    {
        $this->lastRequest = new RequestConstructionSecurityTestRequest($url);
        return $this->lastRequest;
    }
}

final class RequestConstructionSecurityTestAction
{
    private $method;

    public function __construct($method)
    {
        $this->method = $method;
    }

    public function httpMethod()
    {
        return $this->method;
    }
}
