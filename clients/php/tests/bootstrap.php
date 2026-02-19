<?php

require_once __DIR__ . '/../bootstrap.php';

class ClientTestServer
{
    private const READY_PREFIX = 'HAVEAPI_TEST_SERVER_READY';

    private $proc;
    private $pipes = [];
    private $baseUrl;

    public function start(): void
    {
        if ($this->proc) {
            return;
        }

        $cwd = realpath(__DIR__ . '/..');
        $root = realpath(__DIR__ . '/../../..');
        $gemfile = $root . '/servers/ruby/Gemfile';
        $script = $root . '/servers/ruby/test_support/client_test_server.rb';

        $cmd = sprintf(
            'bundle exec ruby %s --port 0 2>&1',
            escapeshellarg($script)
        );

        $env = [];

        foreach ($_ENV as $k => $v) {
            if (is_scalar($v)) {
                $env[$k] = (string) $v;
            }
        }

        foreach ($_SERVER as $k => $v) {
            if (!isset($env[$k]) && is_scalar($v)) {
                $env[$k] = (string) $v;
            }
        }

        $env['BUNDLE_GEMFILE'] = $gemfile;

        if (!isset($env['PATH']) || $env['PATH'] === '') {
            $path = getenv('PATH');
            if ($path) {
                $env['PATH'] = $path;
            }
        }

        $spec = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $this->proc = proc_open($cmd, $spec, $this->pipes, $cwd, $env);

        if (!is_resource($this->proc)) {
            throw new RuntimeException('Failed to start test server');
        }

        stream_set_blocking($this->pipes[1], false);
        stream_set_blocking($this->pipes[2], false);

        $this->waitForReady();
        $this->waitForHealth();
    }

    public function getBaseUrl(): string
    {
        if (!$this->baseUrl) {
            throw new RuntimeException('Test server is not running');
        }

        return $this->baseUrl;
    }

    public function reset(): void
    {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => "Content-Type: application/json\r\n",
                'content' => '{}',
                'ignore_errors' => true,
            ],
        ]);

        $result = file_get_contents($this->baseUrl . '/__reset', false, $context);

        if ($result === false) {
            throw new RuntimeException('Failed to reset test server');
        }

        if (!isset($http_response_header[0]) || strpos($http_response_header[0], '200') === false) {
            throw new RuntimeException('Reset endpoint returned non-200 status');
        }
    }

    public function stop(): void
    {
        if (!$this->proc) {
            return;
        }

        proc_terminate($this->proc);
        proc_close($this->proc);

        foreach ($this->pipes as $pipe) {
            if (is_resource($pipe)) {
                fclose($pipe);
            }
        }

        $this->pipes = [];
        $this->proc = null;
    }

    private function waitForReady(): void
    {
        $deadline = microtime(true) + 30;

        while (microtime(true) < $deadline) {
            $status = proc_get_status($this->proc);
            if (!$status['running']) {
                $output = $this->readOutput();
                throw new RuntimeException('Test server exited early: ' . $output);
            }

            $read = [$this->pipes[1]];
            $write = [];
            $except = [];

            if (stream_select($read, $write, $except, 0, 200000) === 0) {
                continue;
            }

            $line = fgets($this->pipes[1]);
            if ($line === false) {
                continue;
            }

            if (strpos($line, self::READY_PREFIX) !== false) {
                if (preg_match('/' . self::READY_PREFIX . '\\s+(\\S+)/', $line, $matches)) {
                    $this->baseUrl = $matches[1];
                    return;
                }
            }
        }

        throw new RuntimeException('Test server did not start in time');
    }

    private function readOutput(): string
    {
        $output = '';

        foreach ([1, 2] as $idx) {
            if (!isset($this->pipes[$idx]) || !is_resource($this->pipes[$idx])) {
                continue;
            }

            $chunk = stream_get_contents($this->pipes[$idx]);
            if ($chunk !== false) {
                $output .= $chunk;
            }
        }

        return trim($output);
    }

    private function waitForHealth(): void
    {
        $deadline = microtime(true) + 5;

        while (microtime(true) < $deadline) {
            $context = stream_context_create([
                'http' => [
                    'method' => 'GET',
                    'ignore_errors' => true,
                ],
            ]);

            $result = @file_get_contents($this->baseUrl . '/__health', false, $context);

            if ($result !== false && isset($http_response_header[0]) && strpos($http_response_header[0], '200') !== false) {
                return;
            }

            usleep(50000);
        }

        throw new RuntimeException('Test server did not become healthy in time');
    }
}
