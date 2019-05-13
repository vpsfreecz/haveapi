<?php

namespace HaveAPI\Client;

use HaveAPI\Client;

/**
 * Represents a callable resource action.
 */
class Action {
	private $m_name;
	private $description;

	/**
	 * @var Client
	 */
	private $client;

	private $resource;
	private $prepared_path;
	private $args;
	private $lastArgs = array();

	/**
	 * @param Client $client
	 * @param Resource $resource parent
	 * @param string $name action name
	 * @param \stdClass $description action description
	 * @param array $args arguments passed from the parent
	 */
	public function __construct(Client $client, Resource $resource, $name, $description, $args) {
		$this->client = $client;
		$this->resource = $resource;
		$this->m_name = $name;
		$this->description = $description;
		$this->args = $args;
	}

	/**
	 * Inovoke the action.
	 * The return value depends on action's output layout:
	 * - object - ResourceInstance
	 * - object_list - ResourceInstanceList
	 * - hash - Response
	 * - hash_list - Response
	 * @return mixed
	 * @throws Exception\UnresolvedArguments
	 * @throws Exception\ActionFailed
	 */
	public function call() {
		$params = $this->prepareCall(func_get_args());

		$ret = $this->client->call($this, $params);

		$this->prepared_path = null;

		return $ret;
	}

	/**
	 * Invoke the action without interpreting its response.
	 * @return \stdClass response body
	 * @throws Exception\UnresolvedArguments
	 */
	public function directCall() {
		$params = $this->prepareCall(func_get_args());

		$ret = $this->client->directCall($this, $params);

		$this->prepared_path = null;

		return $ret;
	}

	/**
	 * Prepare parameters for the action invocation.
	 */
	protected function prepareCall($func_args) {
		if(!$this->prepared_path)
			$this->prepared_path = $this->path();

		$args = array_merge($this->args, $func_args);

		$cnt = count($args);
		$replaced_cnt = 0;
		$params = array();
		$this->lastArgs = array();

		for($i = 0; $i < $cnt; $i++) {
			$arg = $args[$i];

			if(is_array($arg)) {
				$params = $arg;
				break;
			}

			$this->prepared_path = preg_replace("/\{[a-zA-Z\-_]+\}/", $arg, $this->prepared_path, 1, $replaced_cnt);

			if($replaced_cnt) {
				$this->lastArgs[] = $arg;

			} else {
				$params = $arg;
				break;
			}
		}

		if(preg_match("/\{[a-zA-Z\-_]+\}/", $this->prepared_path))
			throw new Exception\UnresolvedArguments("Cannot call action '{$this->resource->getName()}#{$this->m_name}': unresolved arguments.");

		return $params;
	}

	/**
	 * Set action URL.
	 */
	public function preparePath($path) {
		$this->prepared_path = $path;
	}

	/**
	 * @return string HTTP method
	 */
	public function httpMethod() {
		return $this->description->method;
	}

	/**
	 * @return string raw or prepared URL
	 */
	public function path() {
		if($this->prepared_path)
			return $this->prepared_path;

		return $this->description->path;
	}

	/**
	 * @param string $src direction, input or output
	 * @return string layout for direction
	 */
	public function layout($src) {
		return $this->description->$src->layout;
	}

	/**
	 * @return string namespace
	 */
	public function getNamespace($src) {
		return $this->description->$src->{'namespace'};
	}

	/**
	 * @return \stdClass parameters
	 */
	public function getParameters($direction) {
		return $this->description->{$direction}->parameters;
	}

	/**
	 * @return string action name
	 */
	public function name() {
		return $this->m_name;
	}

	public function getClient() {
		return $this->client;
	}

	/**
	 * @return Resource parent
	 */
	public function getResource() {
		return $this->resource;
	}

	/**
	 * @return array an array of arguments that resulted in creation of this action
	 */
	public function getLastArgs() {
		return $this->lastArgs;
	}

	public function applyArgs($args) {
		$this->args = array_merge($this->args, $args);
	}

	public function __toString() {
		return $this->m_name;
	}
}
