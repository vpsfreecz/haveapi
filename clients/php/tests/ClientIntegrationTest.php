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

        $this->expectException(\HaveAPI\Client\Exception\ActionFailed::class);
        $api->project->task->create(1, []);
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
}
