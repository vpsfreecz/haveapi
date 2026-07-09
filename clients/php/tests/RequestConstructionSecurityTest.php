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
        $client = new RequestConstructionSecurityOAuthClient('https://api.example');
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

    public function testActionPathArgumentsAreEncodedAsPathComponents(): void
    {
        $client = new RequestConstructionSecurityFailingClient();
        $action = $this->newPathAction($client);
        $pathArg = '42?user[name]=alice&_meta[includes]=group__secret';

        try {
            $action->call($pathArg, ['name' => 'alice']);
            $this->fail('Expected simulated client failure');
        } catch (RuntimeException $e) {
            $this->assertSame('simulated call failure', $e->getMessage());
        }

        $this->assertSame(
            ['/v1/users/42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret'],
            $client->callPaths
        );
        $this->assertNull(parse_url($client->callPaths[0], PHP_URL_QUERY));
    }

    public function testAppliedActionPathArgumentsAreEncodedAsPathComponents(): void
    {
        $client = new RequestConstructionSecurityFailingClient();
        $action = $this->newPathAction($client);
        $pathArg = '42?user[name]=alice&_meta[includes]=group__secret';

        $action->applyArgs([$pathArg]);

        try {
            $action->directCall(['name' => 'alice']);
            $this->fail('Expected simulated direct call failure');
        } catch (RuntimeException $e) {
            $this->assertSame('simulated direct call failure', $e->getMessage());
        }

        $this->assertSame(
            ['/v1/users/42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret'],
            $client->directCallPaths
        );
        $this->assertNull(parse_url($client->directCallPaths[0], PHP_URL_QUERY));
    }

    public function testActionPathRejectsAuthoritySwitch(): void
    {
        $client = new RequestConstructionSecurityCaptureClient('https://api.example');
        $action = $this->newRequestAction($client, '@127.0.0.1:8080/internal-metadata');

        try {
            $client->directCall($action, []);
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('action path', $e->getMessage());
        }

        $this->assertNull($client->lastRequest);
    }

    public function testActionPathPreservesApiRootRelativeUrl(): void
    {
        $client = new RequestConstructionSecurityCaptureClient('https://api.example/api');
        $action = $this->newRequestAction($client, '/v1/projects');

        $client->directCall($action, []);

        $this->assertSame('https://api.example/api/v1/projects', $client->lastRequest->uri);
    }

    public function testOAuth2RevocationRejectsCrossOriginBeforeRequest(): void
    {
        $client = new RequestConstructionSecurityOAuthClient('https://api.example');
        $description = (object) [
            'revoke_url' => 'https://attacker.example/collect-token',
        ];
        $auth = new \HaveAPI\Client\Authentication\OAuth2($client, $description, []);

        try {
            $auth->revokeToken(['token' => 'vuln76-secret-access-token']);
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('OAuth2 revoke_url', $e->getMessage());
        }

        $this->assertNull($client->lastRequest);
    }

    public function testOAuth2RevocationAcceptsRelativeSameOriginUrl(): void
    {
        $client = new RequestConstructionSecurityOAuthClient('https://api.example/api');
        $description = (object) [
            'revoke_url' => '/_auth/oauth2/revoke',
        ];
        $auth = new \HaveAPI\Client\Authentication\OAuth2($client, $description, []);

        $auth->revokeToken(['token' => 'same-origin-access-token']);

        $this->assertSame(
            'https://api.example/api/_auth/oauth2/revoke',
            $client->lastRequest->uri
        );
        $this->assertSame(
            'token=same-origin-access-token',
            $client->lastRequest->bodyValue
        );
    }

    public function testOAuth2RevocationAcceptsTrustedCrossOriginUrl(): void
    {
        $client = new RequestConstructionSecurityOAuthClient(
            'https://api.example',
            null,
            'haveapi-client-php',
            ['oauth2_trusted_origins' => ['https://auth.example']]
        );
        $description = (object) [
            'revoke_url' => 'https://auth.example/_auth/oauth2/revoke',
        ];
        $auth = new \HaveAPI\Client\Authentication\OAuth2($client, $description, []);

        $auth->revokeToken(['token' => 'trusted-origin-access-token']);

        $this->assertSame(
            'https://auth.example/_auth/oauth2/revoke',
            $client->lastRequest->uri
        );
        $this->assertSame(
            'token=trusted-origin-access-token',
            $client->lastRequest->bodyValue
        );
    }

    public function testOAuth2TrustedOriginsRequireExactOrigin(): void
    {
        $client = new RequestConstructionSecurityOAuthClient(
            'https://api.example',
            null,
            'haveapi-client-php',
            ['oauth2_trusted_origins' => ['https://auth.example']]
        );
        $description = (object) [
            'revoke_url' => 'https://auth.example.evil/collect-token',
        ];
        $auth = new \HaveAPI\Client\Authentication\OAuth2($client, $description, []);

        try {
            $auth->revokeToken(['token' => 'trusted-origin-access-token']);
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('OAuth2 revoke_url', $e->getMessage());
        }

        $this->assertNull($client->lastRequest);
    }

    public function testOAuth2TokenEndpointRejectsCrossOrigin(): void
    {
        $client = new RequestConstructionSecurityOAuthClient('https://api.example');
        $description = $this->newOAuth2Description([
            'token_url' => 'https://attacker.example/oauth2/token',
        ]);

        try {
            new \HaveAPI\Client\Authentication\OAuth2(
                $client,
                $description,
                $this->newOAuth2Options()
            );
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('OAuth2 token_url', $e->getMessage());
        }

        $this->assertNull($client->lastRequest);
    }

    public function testOAuth2AuthorizeEndpointRejectsCrossOrigin(): void
    {
        $client = new RequestConstructionSecurityOAuthClient('https://api.example');
        $description = $this->newOAuth2Description([
            'authorize_url' => 'https://attacker.example/oauth2/authorize',
        ]);

        try {
            new \HaveAPI\Client\Authentication\OAuth2(
                $client,
                $description,
                $this->newOAuth2Options()
            );
            $this->fail('Expected ProtocolError');
        } catch (\HaveAPI\Client\Exception\ProtocolError $e) {
            $this->assertStringContainsString('OAuth2 authorize_url', $e->getMessage());
        }

        $this->assertNull($client->lastRequest);
    }

    public function testOAuth2EndpointsAcceptTrustedCrossOriginUrls(): void
    {
        $client = new RequestConstructionSecurityOAuthClient(
            'https://api.example',
            null,
            'haveapi-client-php',
            ['oauth2_trusted_origins' => ['https://auth.example']]
        );
        $auth = new \HaveAPI\Client\Authentication\OAuth2(
            $client,
            $this->newOAuth2Description([
                'authorize_url' => 'https://auth.example/_auth/oauth2/authorize',
                'token_url' => 'https://auth.example/_auth/oauth2/token',
                'revoke_url' => 'https://auth.example/_auth/oauth2/revoke',
            ]),
            $this->newOAuth2Options()
        );
        $provider = $this->genericProviderFrom($auth);

        $this->assertSame(
            'https://auth.example/_auth/oauth2/authorize',
            $provider->getBaseAuthorizationUrl()
        );
        $this->assertSame(
            'https://auth.example/_auth/oauth2/token',
            $provider->getBaseAccessTokenUrl([])
        );

        $auth->revokeToken(['token' => 'trusted-origin-access-token']);
        $this->assertSame(
            'https://auth.example/_auth/oauth2/revoke',
            $client->lastRequest->uri
        );
    }

    public function testOAuth2EndpointsAcceptRelativeSameOriginUrls(): void
    {
        $client = new RequestConstructionSecurityOAuthClient('https://api.example/api');
        $auth = new \HaveAPI\Client\Authentication\OAuth2(
            $client,
            $this->newOAuth2Description([
                'authorize_url' => '/_auth/oauth2/authorize',
                'token_url' => '/_auth/oauth2/token',
            ]),
            $this->newOAuth2Options()
        );
        $provider = $this->genericProviderFrom($auth);

        $this->assertSame(
            'https://api.example/api/_auth/oauth2/authorize',
            $provider->getBaseAuthorizationUrl()
        );
        $this->assertSame(
            'https://api.example/api/_auth/oauth2/token',
            $provider->getBaseAccessTokenUrl([])
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
            $this->assertStringContainsString('unresolved path arguments', $e->getMessage());
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
            $this->assertStringContainsString('unresolved path arguments', $e->getMessage());
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

    private function newRequestAction(\HaveAPI\Client $client, $path): \HaveAPI\Client\Action
    {
        $description = (object) [
            'aliases' => [],
            'method' => 'GET',
            'path' => $path,
            'input' => (object) [
                'layout' => 'hash',
                'namespace' => 'probe',
                'parameters' => (object) [],
            ],
            'output' => (object) [
                'layout' => 'hash',
                'namespace' => 'probe',
                'parameters' => (object) [],
            ],
        ];
        $resource = new \HaveAPI\Client\Resource(
            $client,
            'probe',
            (object) [
                'actions' => (object) [],
                'resources' => (object) [],
            ],
            []
        );

        return new \HaveAPI\Client\Action($client, $resource, 'show', $description, []);
    }

    private function newOAuth2Description(array $overrides = []): \stdClass
    {
        return (object) array_merge(
            [
                'authorize_url' => 'https://api.example/_auth/oauth2/authorize',
                'token_url' => 'https://api.example/_auth/oauth2/token',
                'revoke_url' => 'https://api.example/_auth/oauth2/revoke',
            ],
            $overrides
        );
    }

    private function newOAuth2Options(): array
    {
        return [
            'client_id' => 'vuln80-client-id',
            'client_secret' => 'vuln80-client-secret',
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

final class RequestConstructionSecurityCaptureClient extends \HaveAPI\Client
{
    public $lastRequest = null;

    protected function sendRequest($request, $action = null, $params = [])
    {
        $this->lastRequest = $request;

        return (object) ['body' => (object) []];
    }
}

final class RequestConstructionSecurityOAuthClient extends \HaveAPI\Client
{
    public $lastRequest = null;

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
