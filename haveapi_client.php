<?php

namespace HaveAPI;

abstract class AuthProvider {
	protected $client;
	protected $description;
	protected $opts;
	
	public function __construct($client, $description, $opts) {
		$this->client = $client;
		$this->description = $description;
		$this->opts = $opts;
		
		$this->setup();
	}
	
	protected function setup() {
		
	}
	
	abstract public function authenticate($request);
	
	public function queryParameters() {
		return array();
	}
}

class NoAuth extends AuthProvider {
	public function authenticate($request) {
		
	}
}

class BasicAuth extends AuthProvider {
	public function authenticate($request) {
		$request->authenticateWith($this->opts['username'], $this->opts['password']);
	}
}

class TokenAuth extends AuthProvider {
	const HTTP_HEADER = 0;
	const QUERY_PARAMETER = 1;
	
	private $rs;
	private $configured = false;
	private $token;
	private $validTo;
	private $via;
	
	protected function setup() {
		$this->rs = new Resource($this->client, 'token', $this->description->resources->token, array());
		$this->via = isSet($this->opts['via']) ? $this->opts['via'] : self::HTTP_HEADER;
		
		if(isSet($this->opts['token'])) {
			$this->configured = true;
			return;
		}
		
		$this->requestToken();
	}
	
	public function authenticate($request) {
		if(!$this->configured)
			return;
		
		$this->checkValidity();
		
		if($this->via == self::HTTP_HEADER)
			$request->addHeader($this->description->http_header, $this->token);
	}
	
	public function queryParameters() {
		if(!$this->configured || $this->via != self::QUERY_PARAMETER)
			return array();
		
		return array($this->description->query_parameter => $this->token);
	}
	
	protected function requestToken() {
		$ret = $this->rs->request(array(
			'login' => $this->opts['username'],
			'password' => $this->opts['password'],
			'validity' => isSet($this->opts['validity']) ? $this->opts['validity'] : 300
		));
		
		$this->token = $ret->response()->token;
		$this->validTo = strtotime($ret->response()->valid_to);
		
		$this->configured = true;
	}
	
	protected function checkValidity() {
		if($this->validTo < time() && isSet($this->opts['username']) && isSet($this->opts['password']))
			$this->requestToken();
	}
	
	public function getToken() {
		return $this->token;
	}
	
	public function getValidTo() {
		return $this->validTo;
	}
}

class Action {
	private $m_name;
	private $description;
	private $client;
	private $prepared_url;

	public function __construct($client, $name, $description, $args) {
		$this->client = $client;
		$this->m_name = $name;
		$this->description = $description;
		$this->args = $args;
	}
	
	public function call() {
		$this->prepared_url = $this->url();
		$args = $this->args + func_get_args();
		$cnt = count($args);
		$replaced_cnt = 0;
		$params = array();
		
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
		return $this->description->method;
	}
	
	public function url() {
		if($this->prepared_url)
			return $this->prepared_url;
		
		return $this->description->url;
	}
	
	public function layout($src) {
		return $this->description->$src->layout;
	}
	
	public function getNamespace($src) {
		return $this->description->$src->{'namespace'};
	}
	
	public function name() {
		return $this->m_name;
	}
	
	public function __toString() {
		return $this->m_name;
	}
}

class Resource implements \ArrayAccess {
	protected $description;
	protected $client;
	private $args = array();
	
	public function __construct($client, $name, $description, $args) {
		$this->client = $client;
		$this->name = $name;
		$this->description = $description;
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
			return $this->findNestedObject($offset, $this->description);
		
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
	
	protected function findObject($name, $description = null) {
		$this->client->setup();
		
		if(!$description)
			$description = $this->description;
	
		if(isSet($description->actions) && array_key_exists($name, (array) $description->actions)) {
			return new Action($this->client, $name, $description->actions->$name, $this->args);
		
		} if(array_key_exists($name, (array) $description->resources)) {
			return new Resource($this->client, $name, $description->resources->$name, $this->args);
		}
		
		return false;
	}
	
	protected function findNestedObject($path, $description) {
		$parts = explode('.', $path);
		$ask = $this;
		$len = count($parts);
		
		for($i = 0; $i < $len; $i++) {
			$name = $parts[$i];
			
			$obj = $ask->findObject($name, $description);
			
			if($obj instanceof Resource) {
				$ask = $obj;
				$description = null;
				
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

class ResourceInstance extends Resource {

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
			case 'object_list':
			case 'hash':
			case 'hash_list':
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
	private $version;
	private $identity;
	private $authProvider;
	private $queryParams;
	private static $authProviders = array();
	
	public static function registerAuthProvider($name, $class, $force = true) {
		if(!$force && in_array($name, self::$authProviders))
			return;
		
		self::$authProviders[$name] = $class;
	}
	
	public function __construct($uri = 'http://localhost:4567', $version = null, $identity = 'haveapi-client-php') {
		$this->client = $this;
		$this->uri = chop($uri, '/');
		$this->version = $version;
		$this->identity = $identity;
		
		self::registerAuthProvider('none', 'HaveAPI\NoAuth');
		self::registerAuthProvider('basic', 'HaveAPI\BasicAuth');
		self::registerAuthProvider('token', 'HaveAPI\TokenAuth');
		
		$this->authProvider = new NoAuth($this, array(), array());
	}
	
	public function setup($force = false) {
		if(!$force && $this->description)
			return;
		
		$this->description = $this->getDescription();
	}
	
	public function authenticate($method, $opts) {
		if(!array_key_exists($method, self::$authProviders))
			throw new \Exception("Auth method '$method' is not registered");
		
		$this->setup();
		
		$this->authProvider = new self::$authProviders[$method]($this, $this->description->authentication->{$method}, $opts);
		
		$this->setup(true);
	}
	
	public function call($action, $params = array()) {
		$fn = strtolower($action->httpMethod());
		
// 		echo "execute {$action->httpMethod()} {$action->url()}\n<br>\n";
		
		$request = $this->getRequest($fn, $this->uri . $action->url());
		
		if(!$this->sendAsQueryParams($fn))
			$request->body(empty($params) ? '{}' : json_encode(array($action->getNamespace('input') => $params)));
		
		$this->authProvider->authenticate($request);
		
		$response = $this->sendRequest($request, $action, $params);
		
		return new Response($action, $response->body);
	}
	
	protected function getRequest($method, $url) {
		$this->queryParams = array();
		
		$request = \Httpful\Request::$method($url);
		$request->sendsJson();
		$request->expectsJson();
		$request->addHeader('User-Agent', $this->identity);
		
		return $request;
	}
	
	protected function sendRequest($request, $action = null, $params = array()) {
		$this->queryParams += $this->authProvider->queryParameters();
		
		if($action && $this->sendAsQueryParams($action->httpMethod())) {
			foreach($params as $k => $v) {
				$this->queryParams[ $action->getNamespace('input')."[$k]" ] = $v;
			}
		}
		
		if(count($this->queryParams) > 0) {
			$url = $request->uri;
			$first = true;
			
			foreach($this->queryParams as $k => $v) {
				if($first) {
					$url .= '?';
					$first = false;
				} else $url .= '&';
				
				$url .= $k.'='.urlencode($v);
			}
			
			$request->uri = $url;
		}
		
		return $request->send();
	}
	
	protected function sendAsQueryParams($method) {
		return in_array(strtolower($method), array('get', 'options'));
	}
	
	protected function getDescription() {
		$url = $this->uri;
		
		if($this->version)
			$url .= "/v".$this->version."/";
		
		$request = $this->getRequest('options', $url);
		
		if(!$this->version)
			$this->queryParams['describe'] = 'default';
		
		$this->authProvider->authenticate($request);
		
		return $this->sendRequest($request)->body->response;
	}
	
	protected function findObject($name, $description = null) {
		$obj = parent::findObject($name, $description);
		
		if($obj instanceof Resource) {
			$obj->setApiClient($this);
		}
		
		return $obj;
	}
}
