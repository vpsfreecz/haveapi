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

    public function testPreparedPathIsClearedWhenCallThrows(): void
    {
        $client = new RequestConstructionSecurityFailingClient();
        $action = $this->newPathAction($client);

        try {
            $action->call(42, ['name' => 'alice']);
            $this->fail('Expected simulated client failure');
        } catch (RuntimeException $e) {
            $this->assertSame('simulated call failure', $e->getMessage());
        }

        $this->assertSame(['/v1/users/42'], $client->callPaths);

        try {
            $action->call(['name' => 'bob']);
            $this->fail('Expected unresolved path argument');
        } catch (\HaveAPI\Client\Exception\UnresolvedArguments $e) {
            $this->assertStringContainsString('unresolved arguments', $e->getMessage());
        }

        $this->assertSame(['/v1/users/42'], $client->callPaths);
    }

    public function testPreparedPathIsClearedWhenDirectCallThrows(): void
    {
        $client = new RequestConstructionSecurityFailingClient();
        $action = $this->newPathAction($client);

        try {
            $action->directCall(42, ['name' => 'alice']);
            $this->fail('Expected simulated client failure');
        } catch (RuntimeException $e) {
            $this->assertSame('simulated direct call failure', $e->getMessage());
        }

        $this->assertSame(['/v1/users/42'], $client->directCallPaths);

        try {
            $action->directCall(['name' => 'bob']);
            $this->fail('Expected unresolved path argument');
        } catch (\HaveAPI\Client\Exception\UnresolvedArguments $e) {
            $this->assertStringContainsString('unresolved arguments', $e->getMessage());
        }

        $this->assertSame(['/v1/users/42'], $client->directCallPaths);
    }

    public function testTokenAuthRejectsInjectedHeaderName(): void
    {
        $auth = $this->newTokenAuth(
            "X-HaveAPI-Token\r\nX-Injected-Token",
            'vuln97-secret-token'
        );
        $request = \Httpful\Request::get('https://api.example/v1/projects');

        try {
            $auth->authenticate($request);
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('header name', $e->getMessage());
        }

        $this->assertSame([], $request->headers);
    }

    public function testTokenAuthRejectsInjectedHeaderValue(): void
    {
        $auth = $this->newTokenAuth(
            'X-HaveAPI-Token',
            "vuln97-secret-token\r\nX-Injected-Token: yes"
        );
        $request = \Httpful\Request::get('https://api.example/v1/projects');

        try {
            $auth->authenticate($request);
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('header value', $e->getMessage());
        }

        $this->assertSame([], $request->headers);
    }

    public function testTokenAuthAcceptsValidHeaderName(): void
    {
        $auth = $this->newTokenAuth('X-HaveAPI-Token', 'valid-secret-token');
        $request = \Httpful\Request::get('https://api.example/v1/projects');

        $auth->authenticate($request);

        $this->assertSame('valid-secret-token', $request->headers['X-HaveAPI-Token']);
    }

    private function newPathAction(\HaveAPI\Client $client): \HaveAPI\Client\Action
    {
        $resource = new \HaveAPI\Client\Resource($client, 'user', (object) [], []);

        return new \HaveAPI\Client\Action(
            $client,
            $resource,
            'show',
            (object) [
                'path' => '/v1/users/{user_id}',
            ],
            []
        );
    }

    private function newTokenAuth($headerName, $token): \HaveAPI\Client\Authentication\Token
    {
        $description = (object) [
            'resources' => (object) [
                'token' => (object) [
                    'actions' => (object) [],
                    'resources' => (object) [],
                ],
            ],
            'http_header' => $headerName,
            'query_parameter' => 'auth_token',
        ];

        return new \HaveAPI\Client\Authentication\Token(
            new \HaveAPI\Client(),
            $description,
            ['token' => $token]
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

final class RequestConstructionSecurityFailingClient extends \HaveAPI\Client
{
    public $callPaths = [];
    public $directCallPaths = [];

    public function call($action, $params = [])
    {
        $this->callPaths[] = $action->path();
        throw new RuntimeException('simulated call failure');
    }

    public function directCall(\HaveAPI\Client\Action $action, $params = [], &$time = null)
    {
        $this->directCallPaths[] = $action->path();
        throw new RuntimeException('simulated direct call failure');
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
