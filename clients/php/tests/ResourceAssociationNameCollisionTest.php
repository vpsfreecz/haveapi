<?php

use PHPUnit\Framework\TestCase;

final class ResourceAssociationNameCollisionTest extends TestCase
{
    public function testLanguageResourceRemainsDistinctFromClientConfiguration(): void
    {
        $client = new \HaveAPI\Client(
            'https://api.example',
            null,
            'haveapi-client-php-test',
            ['language' => 'cs']
        );
        $client->setDescription($this->description());

        $this->assertSame('cs', $client->getLanguage());
        $this->assertSame('language', $client->language->getName());
        $this->assertSame('language', $client['language']->getName());

        $owner = new \HaveAPI\Client\ResourceInstance(
            $client,
            $client['owner.show'],
            (object) [
                'language' => (object) [
                    'id' => 1,
                    'label' => 'Czech',
                    '_meta' => (object) [
                        'resolved' => true,
                        'path_params' => [1],
                    ],
                ],
            ]
        );

        $this->assertInstanceOf(
            \HaveAPI\Client\ResourceInstance::class,
            $owner->language
        );
        $this->assertSame('language', $owner->language->getName());
        $this->assertSame(1, $owner->language->id);
    }

    private function description(): \stdClass
    {
        $show = static function (\stdClass $parameters, string $namespace): \stdClass {
            return (object) [
                'aliases' => [],
                'blocking' => false,
                'method' => 'GET',
                'path' => '/v1/' . $namespace . '/{' . $namespace . '_id}',
                'input' => (object) [
                    'layout' => 'object',
                    'namespace' => $namespace,
                    'parameters' => (object) [],
                ],
                'output' => (object) [
                    'layout' => 'object',
                    'namespace' => $namespace,
                    'parameters' => $parameters,
                ],
                'meta' => (object) [],
            ];
        };

        $languageParameters = (object) [
            'id' => (object) ['type' => 'Integer'],
            'label' => (object) ['type' => 'String'],
        ];
        $ownerParameters = (object) [
            'language' => (object) [
                'type' => 'Resource',
                'resource' => ['language'],
                'value_id' => 'id',
                'value_label' => 'label',
            ],
        ];

        return (object) [
            'authentication' => (object) [],
            'meta' => (object) ['namespace' => '_meta'],
            'resources' => (object) [
                'language' => (object) [
                    'resources' => (object) [],
                    'actions' => (object) [
                        'show' => $show($languageParameters, 'language'),
                    ],
                ],
                'owner' => (object) [
                    'resources' => (object) [],
                    'actions' => (object) [
                        'show' => $show($ownerParameters, 'owner'),
                    ],
                ],
            ],
        ];
    }
}
