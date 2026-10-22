<?php

use PHPUnit\Framework\TestCase;

final class ClientTestServerTest extends TestCase
{
    public function testStopClosesTheOwnedFixtureListener(): void
    {
        $server = new ClientTestServer();

        try {
            $server->start();
            $url = parse_url($server->getBaseUrl());
            $address = 'tcp://' . $url['host'] . ':' . $url['port'];
            $socket = stream_socket_client($address, $errorCode, $errorMessage, 1);
            $this->assertIsResource($socket);
            fclose($socket);

            $server->stop();
            $socket = @stream_socket_client($address, $errorCode, $errorMessage, 1);

            if (is_resource($socket)) {
                fclose($socket);
                $this->fail('The fixture listener survived stop()');
            }

            $this->assertFalse($socket);
        } finally {
            $server->stop();
        }
    }
}
