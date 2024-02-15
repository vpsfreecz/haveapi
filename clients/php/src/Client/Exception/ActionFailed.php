<?php

namespace HaveAPI\Client\Exception;

/**
 * Thrown when an action fails.
 */
class ActionFailed extends Base
{
    private $response;

    /**
     * @param \HaveAPI\Client\Response $response
     */
    public function __construct($response, $message, $code = 0, $previous = null)
    {
        $this->response = $response;

        parent::__construct($message, $code, $previous);
    }

    /**
     * Return an array of errors.
     * @return array
     */
    public function getErrors()
    {
        return $this->response->getErrors();
    }

    /**
     * Return response from the API.
     * @return \HaveAPI\Client\Response
     */
    public function getResponse()
    {
        return $this->response;
    }
}
