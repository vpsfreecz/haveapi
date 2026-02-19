<?php

use PHPUnit\Framework\TestCase;

final class ClientIntegrationTest extends TestCase
{
    private static $server;
    private static $baseUrl;

    public static function setUpBeforeClass(): void
    {
        self::$server = new ClientTestServer();
        self::$server->start();
        self::$baseUrl = self::$server->getBaseUrl();
    }

    public static function tearDownAfterClass(): void
    {
        if (self::$server) {
            self::$server->stop();
        }
    }

    protected function setUp(): void
    {
        self::$server->reset();
    }

    public function testSetupReadsDocs(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->setup();

        $this->assertFalse($api->project);
    }

    public function testBasicAuthUnlocksResources(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        $projects = $api->project->list();
        $this->assertGreaterThanOrEqual(2, count($projects));

        $project = $api->project->find($projects[0]->id);
        $this->assertEquals($projects[0]->id, $project->id);
    }

    public function testTokenAuthFlow(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('token', ['user' => 'user', 'password' => 'pass']);

        $token = $api->getAuthenticationProvider()->getToken();
        $this->assertNotEmpty($token);

        $tokenClient = new \HaveAPI\Client(self::$baseUrl);
        $tokenClient->authenticate('token', ['token' => $token]);

        $projects = $tokenClient->project->list();
        $this->assertGreaterThanOrEqual(2, count($projects));
    }

    public function testNestedResourceArguments(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        $projectId = $api->project->list()[0]->id;

        $taskA = $api->project->task->create($projectId, ['label' => 'alpha']);
        $this->assertEquals('alpha', $taskA->label);

        $taskB = $api->project($projectId)->task->create(['label' => 'beta']);
        $this->assertEquals('beta', $taskB->label);
    }

    public function testServerSideValidationError(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        try {
            $api->project->task->create(1, []);
            $this->fail('Expected ValidationError');
        } catch (\HaveAPI\Client\Exception\ValidationError $e) {
            $errors = $e->getErrors();
            $this->assertArrayHasKey('label', $errors);
            $this->assertContains('required parameter missing', $errors['label']);
        }
    }

    public function testBlockingActionMeta(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        $projectId = $api->project->list()[0]->id;
        $task = $api->project($projectId)->task->create(['label' => 'run']);

        $response = $api->project->task->run($projectId, $task->id);
        $meta = $response->getMeta();

        $this->assertNotEmpty($meta->action_state_id);
    }

    public function testErrorAction(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);

        try {
            $api->test->fail();
            $this->fail('Expected ActionFailed');
        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $this->assertStringContainsString('forced failure', $e->getMessage());
        }
    }

    public function testTypedInputValidCoercions(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);

        $resp = $api->test->echo([
            'i' => ' 42 ',
            'f' => 5,
            'b' => 'yes',
            'dt' => '2020-01-01T00:00:00Z',
            's' => 123,
            't' => false,
        ]);

        $this->assertTrue($resp->isOk());
        $this->assertSame(42, $resp['i']);
        $this->assertEquals(5.0, $resp['f']);
        $this->assertTrue($resp['b']);
        $this->assertMatchesRegularExpression('/\\A2020-01-01T00:00:00(?:Z|\\+00:00)\\z/', $resp['dt']);
        $this->assertSame('123', $resp['s']);
        $this->assertSame('false', $resp['t']);

        $resp = $api->test->echo([
            'i' => 1,
            'f' => '1e3',
            'b' => true,
            'dt' => '2020-01-01T00:00:00Z',
            's' => 'ok',
            't' => 'ok',
        ]);

        $this->assertTrue($resp->isOk());
        $this->assertEquals(1000.0, $resp['f']);
    }

    public function testTypedInputMissingRequiredIsRejectedLocally(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);

        try {
            $api->test->echo([
                'f' => 1,
                'b' => true,
                'dt' => '2020-01-01T00:00:00Z',
                's' => 'ok',
                't' => 'ok',
            ]);
            $this->fail('Expected ValidationError');
        } catch (\HaveAPI\Client\Exception\ValidationError $e) {
            $errors = $e->getErrors();
            $this->assertArrayHasKey('i', $errors);
            $this->assertContains('required parameter missing', $errors['i']);
        }
    }

    public function testTypedInputInvalidValuesAreRejectedLocally(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $base = [
            'i' => 1,
            'f' => 1.0,
            'b' => true,
            'dt' => '2020-01-01T00:00:00Z',
            's' => 'ok',
            't' => 'ok',
        ];

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['i' => 'abc']));
        }, 'i', 'not a valid integer');

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['f' => 'abc']));
        }, 'f', 'not a valid float');

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['b' => 'maybe']));
        }, 'b', 'not a valid boolean');

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['dt' => '2020-02-30']));
        }, 'dt', 'not in ISO 8601 format');

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['s' => ['x']]));
        }, 's', 'not a valid string');

        $this->assertValidationError(function () use ($api, $base) {
            $api->test->echo(array_merge($base, ['t' => ['x']]));
        }, 't', 'not a valid string');
    }

    public function testTypedInputResourceCoercion(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        $project = $api->project->list()[0];

        $resp = $api->test->echo_resource(['project' => $project]);
        $this->assertTrue($resp->isOk());
        $this->assertSame($project->id, $resp['project']);

        $this->assertValidationError(function () use ($api) {
            $api->test->echo_resource(['project' => 'abc']);
        }, 'project', 'not a valid resource id');
    }

    public function testOptionalResourceNullIsAccepted(): void
    {
        $api = new \HaveAPI\Client(self::$baseUrl);
        $api->authenticate('basic', ['user' => 'user', 'password' => 'pass']);

        $resp = $api->test->echo_resource_optional(['project' => null]);
        $this->assertTrue($resp->isOk());
        $this->assertTrue($resp['project_provided']);
        $this->assertTrue($resp['project_nil']);
        $this->assertFalse(isset($resp['project']));
    }

    private function assertValidationError(callable $fn, string $param, string $message): void
    {
        try {
            $fn();
            $this->fail('Expected ValidationError');
        } catch (\HaveAPI\Client\Exception\ValidationError $e) {
            $errors = $e->getErrors();
            $this->assertArrayHasKey($param, $errors);
            $this->assertContains($message, $errors[$param]);
        }
    }
}
