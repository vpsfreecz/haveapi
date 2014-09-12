<?php

namespace HaveAPI;

class ActionFailed extends \Exception {
	private $response;
	
	public function __construct($response, $message, $code = 0, $previous = null) {
		$this->response = $response;
		
		parent::__construct($message, $code, $previous);
	}
	
	public function errors() {
		return $this->response->errors();
	}
}

class AuthenticationFailed extends \Exception {
}

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
	private $resource;
	private $prepared_url;
	private $args;
	private $lastArgs = array();

	public function __construct($client, $resource, $name, $description, $args) {
		$this->client = $client;
		$this->resource = $resource;
		$this->m_name = $name;
		$this->description = $description;
		$this->args = $args;
	}
	
	public function call() {
		$params = $this->prepareCall(func_get_args());
		
		$ret = $this->client->call($this, $params);
		
		$this->prepared_url = null;
		
		return $ret;
	}
	
	public function directCall() {
		$params = $this->prepareCall(func_get_args());
		
		$ret = $this->client->directCall($this, $params);
		
		$this->prepared_url = null;
		
		return $ret;
	}
	
	protected function prepareCall($func_args) {
		if(!$this->prepared_url)
			$this->prepared_url = $this->url();
		
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
			
			$this->prepared_url = preg_replace("/:[a-zA-Z\-_]+/", $arg, $this->prepared_url, 1, $replaced_cnt);
			
			if($replaced_cnt) {
				$this->lastArgs[] = $arg;
				
			} else {
				$params = $arg;
				break;
			}
		}
		
		if(preg_match("/:[a-zA-Z\-_]+/", $this->prepared_url))
			throw new ActionFailed("Cannot call action '{$this->m_name}': unresolved arguments.");
		
		return $params;
	}
	
	public function prepareUrl($url) {
		$this->prepared_url = $url;
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
	
	public function getResource() {
		return $this->resource;
	}
	
	public function getLastArgs() {
		return $this->lastArgs;
	}
	
	public function __toString() {
		return $this->m_name;
	}
}

class Resource implements \ArrayAccess {
	protected $description;
	protected $client;
	protected $name;
	protected $args = array();
	
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
	
	public function getName() {
		return $this->name;
	}
	
	public function getDescription() {
		return $this->description;
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
		
		throw new ActionFailed("'$name' is not an action nor a resource.");
	}
	
	public function newInstance() {
		return new ResourceInstance($this->client, $this->create, null);
	}
	
	protected function findObject($name, $description = null) {
		$this->client->setup();
		
		if(!$description)
			$description = $this->description;
	
		if(isSet($description->actions)) {
			foreach($description->actions as $searched_name => $desc) {
				if($searched_name == $name || in_array($name, $desc->aliases)) {
					return new Action($this->client, $this, $searched_name, $description->actions->$searched_name, $this->args);
				}
			}
		}
		
		if(array_key_exists($name, (array) $description->resources)) {
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
	protected $persistent = false;
	protected $resolved = false;
	protected $response;
	protected $attrs = array();
	protected $action;
	protected $associations = array();
	
	public function __construct($client, $action, $response) {
		$r = $action->getResource();
		
		parent::__construct($client, $r->getName(), $r->getDescription(), $action->getLastArgs());
		
		$this->action = $action;
		$this->response = $response;
		
		if($response) {
			$this->persistent = true;
			
			if($response instanceof Response) {
				$this->attrs = (array) $response->response();
				
			} else {
				$this->attrs = (array) $response;
				$this->args[] = $this->id;
			}
			
		} else {
			$this->persistent = false;
			$this->defineStubAttrs();
		}
	}
	
	public function newInstance() {
		throw \Exception('Cannot create a new instance from existing instance');
	}
	
	public function apiResponse() {
		return $this->response instanceof Response ? $this->response : null;
	}
	
	public function attributes() {
		return $this->attrs;
	}
	
	public function __get($name) {
		$id = false;
		
		if($this->endsWith($name, '_id')) {
			$name = substr($name, 0, -3);
			$id = true;
		}
		
		if(array_key_exists($name, $this->attrs)) {
			$param = $this->description->actions->{$this->action->name()}->output->parameters->{$name};
			
			switch($param->type) {
				case 'Resource':
					if($id)
						return $this->attrs[$name]->{ $param->value_id };
					
					if(isSet($this->associations[$name]))
						return $this->associations[$name];
					
					$action = $this->client[ implode('.', $param->resource) ]->show;
					$action->prepareUrl($this->attrs[$name]->url);
					
					return $this->associations[$name] = $action->call();
					
				default:
					return $this->attrs[$name];
			}
		}
		
		return parent::__get($name);
	}
	
	public function __set($name, $value) {
		$id = false;
		
		if($this->endsWith($name, '_id')) {
			$name = substr($name, 0, -3);
			$id = true;
		}
		
		if(array_key_exists($name, $this->attrs)) {
			$param = $this->description->actions->{$this->action->name()}->output->parameters->{$name};
			
			switch($param->type) {
				case 'Resource':
					if($id) {
						$this->attrs[$name]->{ $param->value_id } = $value;
						break;
					}
					
					$this->associations[$name] = $value;
					$this->attrs[$name]->{ $param->value_id } = $value->{ $param->value_id };
					$this->attrs[$name]->{ $param->value_label } = $value->{ $param->value_label };
					
					break;
					
				default:
					$this->attrs[$name] = $value;
			}
			
			return;
		}
		
		$trace = debug_backtrace();
		trigger_error(
			'Undefined property via __get(): ' . $name .
			' in ' . $trace[0]['file'] .
			' on line ' . $trace[0]['line'],
			E_USER_NOTICE
		);
        return null;
	}
	
	public function save() {
		if($this->persistent) {
			$action = $this->{'update'};
			$action->directCall($this->attrsForApi($action));
			
		} else {
			// insert
			$action = $this->{'create'};
			$ret = new Response($action, $action->directCall($this->attrsForApi($action)));
			
			if($ret->isOk()) {
				$this->attrs = array_merge($this->attrs, (array) $ret->response());
				
			} else {
				throw new ActionFailed($ret, "Action '".$action->name()."' failed: ".$ret->message());
			}
			
			$this->persistent = true;
		}
	}
	
	protected function attrsForApi($action) {
		$ret = array();
		$desc = $this->description->actions->{$action}->input->parameters;
		
		foreach($this->attrs as $k => $v) {
			if(!isSet($desc->{$k}))
				continue;
			
			$param = $desc->{$k};
			
			switch($param->type) {
				case 'Resource':
					$ret[$k] = $v->{ $param->{'value_id'} };
					break;
				
				default:
					$ret[$k] = $v;
			}
		}
		
		return $ret;
	}
	
	protected function defineStubAttrs() {
		$params = $this->description->actions->{$this->action->name()}->input->parameters;
		
		foreach($params as $name => $desc) {
			switch($desc->type) {
				case 'Resource':
					$c = new \stdClass();
					$c->{$desc->value_id} = null;
					$c->{$desc->value_label} = null;
					
					$this->attrs[$name] = $c;
					break;
				
				default:
					$this->attrs[$name] = null;
			}
		}
	}
	
	protected function endsWith($str, $ending) {
		return $ending === "" || substr($str, -strlen($ending)) === $ending;
	}
}

class ResourceInstanceList implements \ArrayAccess, \Iterator {
	private $items = array();
	private $index = 0;
	private $response;
	
	public function __construct($client, $action, $response) {
		$this->response = $response;
		
		foreach($response->response() as $item) {
			$this->items[] = new ResourceInstance($client, $action, $item);
		}
	}
	
	public function count() {
		return count($this->items);
	}
	
	public function apiResponse() {
		return $this->response;
	}
	
	public function first() {
		return $this->items[0];
	}
	
	public function last() {
		return $this->items[ $this->count() - 1 ];
	}
	
	public function asArray() {
		return $this->items;
	}
	
	// ArrayAccess
	public function offsetExists($offset) {
		return isSet($this->items[$offset]);
	}
	
	public function offsetGet($offset) {
		return $this->items[$offset];
	}
	
	public function offsetSet($offset, $value) {
		$this->items[$offset] = $value;
	}
	
	public function offsetUnset($offset) {
		unset($this->items[$offset]);
	}
	
	// Iterator
	public function current() {
		return $this->items[$this->index];
	}
	
	public function key() {
		return $this->index;
	}
	
	public function next() {
		++$this->index;
	}
	
	public function rewind() {
		$this->index = 0;
	}
	
	public function valid() {
		return isSet($this->items[$this->index]);
	}
}

class Response implements \ArrayAccess {
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
	
	// ArrayAccess
	public function offsetExists($offset) {
		$r = $this->response();
		
		return isSet($r->{$offset});
	}
	
	public function offsetGet($offset) {
		$r = $this->response();
		
		return $r->{$offset};
	}
	
	public function offsetSet($offset, $value) {
		$r = $this->response();
		
		$r->{$offset} = $value;
	}
	
	public function offsetUnset($offset) {
		$r = $this->response();
		
		unset($r->{$offset});
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
		
		$this->description = $this->fetchDescription();
	}
	
	public function authenticate($method, $opts) {
		if(!array_key_exists($method, self::$authProviders))
			throw new AuthenticationFailed("Auth method '$method' is not registered");
		
		$this->setup();
		
		$this->authProvider = new self::$authProviders[$method]($this, $this->description->authentication->{$method}, $opts);
		
		$this->setup(true);
	}
	
	public function call($action, $params = array()) {
		$response = new Response($action, $this->directCall($action, $params));
		
		if(!$response->isOk()) {
			throw new ActionFailed($response, "Action '".$action->name()."' failed: ".$ret->message());
		}
		
		switch($action->layout('output')) {
			case 'object':
				return new ResourceInstance($this->client, $action, $response);
			
			case 'object_list':
				return new ResourceInstanceList($this->client, $action, $response);
			
			default:
				return $response;
		}
	}
	
	public function directCall($action, $params = array()) {
		$fn = strtolower($action->httpMethod());
		
// 		echo "execute {$action->httpMethod()} {$action->url()}\n<br>\n";
		
		$request = $this->getRequest($fn, $this->uri . $action->url());
		
		if(!$this->sendAsQueryParams($fn))
			$request->body(empty($params) ? '{}' : json_encode(array($action->getNamespace('input') => $params)));
		
		$this->authProvider->authenticate($request);
		
		return $this->sendRequest($request, $action, $params)->body;
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
	
	protected function fetchDescription() {
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
