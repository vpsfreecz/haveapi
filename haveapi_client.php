<?php

namespace HaveAPI;

class Action {
	private $m_name;
	private $options;
	private $client;
	private $prepared_url;

	public function __construct($client, $name, $options, $args) {
		$this->client = $client;
		$this->m_name = $name;
		$this->options = $options;
		$this->args = $args;
	}
	
	public function call() {
		$this->prepared_url = $this->url();
		$args = $this->args + func_get_args();
		$cnt = count($args);
		$replaced_cnt = 0;
		$params = [];
		
		for($i = 0; $i < $cnt; $i++) {
			$arg = $args[$i];
			
			if(is_array($arg)) {
				$params = $arg;
				break;
			}
			
			$this->prepared_url = preg_replace("/:[a-zA-Z\-_]+/", $arg, $this->prepared_url, 1, $replaced_cnt);
			
			if(!$replaced_cnt) {
				$params = $arg;
				break;
			}
		}
		
		if(preg_match("/:[a-zA-Z\-_]+/", $this->prepared_url))
			throw new \Exception("Cannot call action '{$this->m_name}': unresolved arguments.");
	
		$ret = $this->client->call($this, $params);
		
		$this->prepared_url = null;
		
		return $ret;
	}
	
	public function httpMethod() {
		return $this->options->method;
	}
	
	public function url() {
		if($this->prepared_url)
			return $this->prepared_url;
		
		return $this->options->url;
	}
	
	public function layout($src) {
		return $this->options->$src->layout;
	}
	
	public function getNamespace($src) {
		return $this->options->$src->{'namespace'};
	}
	
	public function name() {
		return $this->m_name;
	}
	
	public function __toString() {
		return $this->m_name;
	}
}

class Resource implements \ArrayAccess {
	protected $options;
	private $client;
	private $args = array();
	
	public function __construct($client, $name, $options, $args) {
		$this->client = $client;
		$this->name = $name;
		$this->options = $options;
		$this->args = $args;
	}
	
	public function setApiClient($c) {
		$this->client = $c;
	}
	
	public function setArguments($args) {;
		$this->args = $args;
	}
	
	public function offsetExists($offset) {
		
	}
	
	public function offsetGet($offset) {
		if(strpos($offset, '.') === false)
			return $this->findObject($offset);
		
		else
			return $this->findNestedObject($offset, $this->options);
		
	}
	
	public function offsetSet($offset, $value) {
		
	}
	
	public function offsetUnset($offset) {
		
	}
	
	public function __toString() {
		return $this->name;
	}
	
	public function __get($name) {
		return $this->findObject($name);
	}
	
	public function __call($name, $arguments) {
		$obj = $this->findObject($name);
		
		if($obj instanceof Action)
			return call_user_func_array(array($obj, 'call'), $arguments);
		
		if($obj instanceof Resource) {
			$obj->setArguments(array_merge($this->args, $arguments));
			return $obj;
		}
		
		throw new \Exception("'$name' is not an action nor a resource.");
	}
	
	protected function findObject($name, $options = null) {
		if(!$options)
			$options = $this->options;
	
		if(isSet($options->actions) && array_key_exists($name, (array) $options->actions)) {
			return new Action($this->client, $name, $options->actions->$name, $this->args);
		
		} if(array_key_exists($name, (array) $options->resources)) {
			return new Resource($this->client, $name, $options->resources->$name, $this->args);
		}
		
		return false;
	}
	
	protected function findNestedObject($path, $options) {
		$parts = explode('.', $path);
		$ask = $this;
		$len = count($parts);
		
		for($i = 0; $i < $len; $i++) {
			$name = $parts[$i];
			
			$obj = $ask->findObject($name, $options);
			
			if($obj instanceof Resource) {
				$ask = $obj;
				$options = null;
				
			} else if($obj === null) {
				throw new \Exception("Resource or action '$name' not found.");
				
			} else if($obj instanceof Action && $i < $len-1) {
				throw new \Exception("Found action '$name' but path does not end here.");
				
			} else {
				return $obj;
			}
		}
		
		return $ask;
	}
}

class Response {
	private $action;
	private $envelope;
	
	public function __construct($action, $envelope) {
		$this->action = $action;
		$this->envelope = $envelope;
	}
	
	public function isOk() {
		return $this->envelope->status;
	}
	
	public function message() {
		return $this->envelope->message;
	}
	
	public function response() {
		if(!$this->isOk())
			throw new \Exception("Action '".$this->action->name()."' failed: ".$this->message());
		
		$l = $this->action->layout('output');
		
		switch($l) {
			case 'object':
			case 'list':
				return $this->envelope->response->{$this->action->getNamespace('output')};
				
			default:
				return $this->envelope->response;
		}
	}
	
	public function errors() {
		return $this->envelope->errors;
	}
	
	public function __toString() {
		return json_encode($this->response());
	}
}

class Client extends Resource {
	private $uri;
	private $user = null;
	private $password;
	
	public function __construct($uri = 'http://localhost:4567') {
		$this->uri = $uri;
		
		$description = \Httpful\Request::options($uri)
			->expectsJson()
			->send()->body;
		
		$this->options = $description->versions->{$description->default_version};
	}
	
	public function login($user, $password) {
		$this->user = $user;
		$this->password = $password;
	}
	
	public function call($action, $params = array()) {
		$fn = strtolower($action->httpMethod());
		
		echo "execute {$action->httpMethod()} {$action->url()}\n<br>\n";
		
		$request = \Httpful\Request::$fn($this->uri."/".$action->url());
		$request->sendsJson();
		$request->expectsJson();
		$request->body(empty($params) ? '{}' : json_encode([$action->getNamespace('input') => $params]));
		
		if($this->user)
			$request->authenticateWith($this->user, $this->password);
		
		$response = $request->send();
		
		return new Response($action, $response->body);
	}
	
	protected function findObject($name, $options = null) {
		$obj = parent::findObject($name, $options);
		
		if($obj instanceof Resource) {
			$obj->setApiClient($this);
		}
		
		return $obj;
	}
}
