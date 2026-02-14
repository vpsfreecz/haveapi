<?php

namespace HaveAPI\Client\Exception;

use HaveAPI\Client\Action;

/**
 * Thrown when input parameters fail local validation.
 */
class ValidationError extends Base
{
    private $errors;

    /**
     * @param Action|string $actionName
     * @param array $errors
     */
    public function __construct($actionName, array $errors, $message = null, $code = 0, $previous = null)
    {
        $this->errors = $errors;

        if ($message === null) {
            if ($actionName instanceof Action) {
                $resource = $actionName->getResource();
                $actionLabel = $resource ? $resource->getName() . '#' . $actionName->name() : $actionName->name();
                $message = "Input parameters not valid for action '" . $actionLabel . "'";
            } elseif (is_string($actionName) && $actionName !== '') {
                $message = "Input parameters not valid for action '" . $actionName . "'";
            } else {
                $message = 'Input parameters not valid';
            }
        }

        parent::__construct($message, $code, $previous);
    }

    public function getErrors(): array
    {
        return $this->errors;
    }
}
