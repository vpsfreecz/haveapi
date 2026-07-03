<?php

use PHPUnit\Framework\TestCase;

final class BootstrapTest extends TestCase
{
    public function testStandaloneBootstrapLoadsI18nClasses(): void
    {
        $code = <<<'PHP'
            require "bootstrap.php";
            new \HaveAPI\Client(
                "https://api.example",
                null,
                "haveapi-client-php-test",
                ["language" => "cs"]
            );
            echo "ok\n";
            PHP;

        $cmd = implode(' ', [
            escapeshellarg(PHP_BINARY),
            '-r',
            escapeshellarg($code),
        ]);
        $cwd = escapeshellarg(realpath(__DIR__ . '/..'));
        $output = [];
        $exitCode = 0;

        exec("cd $cwd && $cmd 2>&1", $output, $exitCode);

        $this->assertSame(0, $exitCode, implode("\n", $output));
        $this->assertSame(['ok'], $output);
    }
}
