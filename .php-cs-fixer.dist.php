<?php

$finder = (new PhpCsFixer\Finder())
    ->in(__DIR__)
    ->notPath('clients/php/src/Client/I18nMessages.php')
;

return (new PhpCsFixer\Config())
    ->setRules([
        '@PER-CS3x0' => true,
    ])
    ->setFinder($finder)
;
