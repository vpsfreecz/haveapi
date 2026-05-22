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

    public function __construct($uri)
    {
        $this->uri = $uri;
    }

    public function send()
    {
        return $this;
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
