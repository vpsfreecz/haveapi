<?php

namespace HaveAPI;

/**
 * Thrown when an action fails.
 */
class ActionFailed extends \Exception {
	private $response;
	
	public function __construct($response, $message, $code = 0, $previous = null) {
		$this->response = $response;
		
		parent::__construct($message, $code, $previous);
	}
	
	/**
	 * Return an array of errors.
	 * @return array
	 */
	public function errors() {
		return $this->response->errors();
	}
}

/**
 * Thrown when an authentication fails.
 */
class AuthenticationFailed extends \Exception {
}

/**
 * Base class extended by all authentication providers.
 */
abstract class AuthProvider {
	protected $client;
	protected $description;
	protected $opts;
	
	/**
	 * @param Client $client
	 * @param \stdClass $description description of this auth provider
	 * @param array $opts options passed on to the provider
	 */
	public function __construct($client, $description, $opts) {
		$this->client = $client;
		$this->description = $description;
		$this->opts = $opts;
		
		$this->setup();
	}
	
	/**
	 * Called right after the constructor.
	 * Overload it to setup your authentication provider.
	 */
	protected function setup() {
		
	}
	
	/**
	 * Authenticate request to the API.
	 * 
	 * Called for every request sent to the API.
	 * @param \Httpful\Request $request
	 */
	abstract public function authenticate($request);
	
	/**
	 * Return query parameters to be sent in the request.
	 * 
	 * Called for every request sent to the API.
	 * @return array
	 */
	public function queryParameters() {
		return array();
	}
}

/**
 * Used when no authentication provider is selected. Does no authentication.
 */
class NoAuth extends AuthProvider {
	public function authenticate($request) {
		
	}
}

/**
 * Provider for HTTP basic authentication.
 * 
 * It accepts `username` and `password` as options.
 */
class BasicAuth extends AuthProvider {
	public function authenticate($request) {
		$request->authenticateWith($this->opts['username'], $this->opts['password']);
	}
}

/**
 * Provider for token authentication.
 *
 * Accepts either a `token` or `username` and `password` to acquire a token.
 * Option `via` determines how the token is sent to the API. It defaults
 * to TokenAuth::HTTP_HEADER.
 */
class TokenAuth extends AuthProvider {
	const HTTP_HEADER = 0;
	const QUERY_PARAMETER = 1;
	
	private $rs;
	private $configured = false;
	private $token;
	private $validTo = null;
	private $via;
	
	/**
	 * Request a new token if it isn't in the options.
	 */
	protected function setup() {
		$this->rs = new Resource($this->client, 'token', $this->description->resources->token, array());
		$this->via = isSet($this->opts['via']) ? $this->opts['via'] : self::HTTP_HEADER;
		
		if(isSet($this->opts['token'])) {
			$this->configured = true;
			$this->token = $this->opts['token'];
			return;
		}
		
		$this->requestToken();
	}
	
	/**
	 * Add token header if configured. Checks token validity.
	 */
	public function authenticate($request) {
		if(!$this->configured)
			return;
		
		$this->checkValidity();
		
		if($this->via == self::HTTP_HEADER)
			$request->addHeader($this->description->http_header, $this->token);
	}
	
	/**
	 * Returns token query parameter if configured.
	 */
	public function queryParameters() {
		if(!$this->configured || $this->via != self::QUERY_PARAMETER)
			return array();
		
		return array($this->description->query_parameter => $this->token);
	}
	
	/**
	 * Request a new token from the API.
	 */
	protected function requestToken() {
		$ret = $this->rs->request(array(
			'login' => $this->opts['username'],
			'password' => $this->opts['password'],
			'lifetime' => $this->translateLifetime(isSet($this->opts['lifetime']) ? $this->opts['lifetime'] : 'renewable_auto'),
			'interval' => isSet($this->opts['interval']) ? $this->opts['interval'] : 300
		));
		
		$this->token = $ret->response()->token;
		
		$v = $ret->response()->valid_to;
		
		if($v)
			$this->validTo = strtotime($v);
		
		$this->configured = true;
	}
	
	/**
	 * Get a new token if the current one expired.
	 */
	protected function checkValidity() {
		if($this->validTo && $this->validTo < time() && isSet($this->opts['username']) && isSet($this->opts['password']))
			$this->requestToken();
	}
	
	/**
	 * @return string the token
	 */
	public function getToken() {
		return $this->token;
	}
	
	/**
	 * @return int expiration time
	 */
	public function getValidTo() {
		return $this->validTo;
	}
	
	private function translateLifetime($lifetime) {
		$options = array('fixed', 'renewable_manual', 'renewable_auto', 'permanent');
		return array_search($lifetime, $options);
	}
}

/**
 * Represents a callable resource action.
 */
class Action {
	private $m_name;
	private $description;
	private $client;
	private $resource;
	private $prepared_url;
	private $args;
	private $lastArgs = array();
	
	/**
	 * @param Client $client
	 * @param Resource $resource parent
	 * @param string $name action name
	 * @param \stdClass $description action description
	 * @param array $args arguments passed from the parent
	 */
	public function __construct($client, $resource, $name, $description, $args) {
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
	 */
	public function call() {
		$params = $this->prepareCall(func_get_args());
		
		$ret = $this->client->call($this, $params);
		
		$this->prepared_url = null;
		
		return $ret;
	}
	
	/**
	 * Invoke the action without interpreting its response.
	 * @return \stdClass response body
	 */
	public function directCall() {
		$params = $this->prepareCall(func_get_args());
		
		$ret = $this->client->directCall($this, $params);
		
		$this->prepared_url = null;
		
		return $ret;
	}
	
	/**
	 * Prepare parameters for the action invocation.
	 */
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
	
	/**
	 * Set action URL.
	 */
	public function prepareUrl($url) {
		$this->prepared_url = $url;
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
	public function url() {
		if($this->prepared_url)
			return $this->prepared_url;
		
		return $this->description->url;
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
	 * @return string action name
	 */
	public function name() {
		return $this->m_name;
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
	
	public function __toString() {
		return $this->m_name;
	}
}

/**
 * A resource in the API.
 */
class Resource implements \ArrayAccess {
	protected $description;
	protected $client;
	protected $name;
	protected $args = array();
	
	/**
	 * @param Client $client
	 * @param string $name resource name
	 * @param \stdClass $description
	 * @param array $args arguments passed from the parent
	 */
	public function __construct($client, $name, $description, $args) {
		$this->client = $client;
		$this->name = $name;
		$this->description = $description;
		$this->args = $args;
	}
	
	/**
	 * Set client instance.
	 * @param Client $c
	 */
	public function setApiClient($c) {
		$this->client = $c;
	}
	
	/**
	 * Set an array of arguments.
	 * @param array $args
	 */
	public function setArguments($args) {;
		$this->args = $args;
	}
	
	/**
	 * @return string resource name
	 */
	public function getName() {
		return $this->name;
	}
	
	/**
	 * @return \stdClass description
	 */
	public function getDescription() {
		return $this->description;
	}
	
	public function offsetExists($offset) {
		
	}
	
	/**
	 * Return child resource or action.
	 * @return mixed
	 */
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
	
	/**
	 * Return child resource or action.
	 * @return mixed
	 */
	public function __get($name) {
		return $this->findObject($name);
	}
	
	/**
	 * Invoke an action and return its response or a resource with provided arguments.
	 * @return mixed
	 */
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
	
	/**
	 * Create a new resource object instance.
	 * @return ResourceInstance
	 */
	public function newInstance() {
		return new ResourceInstance($this->client, $this->create, null);
	}
	
	/**
	 * Find an action or a resource with $name in $description.
	 * @param string name to be found
	 * @param \stdClass description to be searched in
	 */
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
	
	/**
	 * Find and return an action or a resource which may be nested (names separated by dot).
	 * Used for array access method.
	 * @return mixed
	 */
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

/**
 * Resource object instance.
 */
class ResourceInstance extends Resource {
	protected $persistent = false;
	protected $resolved = false;
	protected $response;
	protected $attrs = array();
	protected $action;
	protected $associations = array();
	
	/**
	 * If $response is NULL, created instance is not persistent.
	 * @param Client $client
	 * @param Action $action
	 * @param mixed $response Response or \stdclass
	 */
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
	
	/**
	 * Do not allow creating an instance from instance.
	 */
	public function newInstance() {
		throw \Exception('Cannot create a new instance from existing instance');
	}
	
	/**
	 * @return Response
	 */
	public function apiResponse() {
		return $this->response instanceof Response ? $this->response : null;
	}
	
	/**
	 * Returns all resource parameters.
	 * @return array
	 */
	public function attributes() {
		return $this->attrs;
	}
	
	/**
	 * Handle resource objecti nstance parameters. Resource parameters also have <name>_id properties,
	 * which returns IDs without resolving the associated resource.
	 * @return mixed
	 */
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
	
	/**
	 * Handle resource object instance parameters.
	 */
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
	
	/**
	 * Create the resource object if it isn't persistent, update it if it is.
	 */
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
	
	/**
	 * Returns an array of parameters ready to be sent to the API.
	 * @return array
	 */
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
	
	/**
	 * Create initial - NULL - resource object instance parameters.
	 */
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
	
	/**
	 * Return true if $str ends with $ending.
	 * @return boolean
	 */
	protected function endsWith($str, $ending) {
		return $ending === "" || substr($str, -strlen($ending)) === $ending;
	}
}

/**
 * A list of resource object instances.
 */
class ResourceInstanceList implements \ArrayAccess, \Iterator {
	private $items = array();
	private $index = 0;
	private $response;
	
	/**
	 * @param Client $client
	 * @param Action $action
	 * @param Response $response
	 */
	public function __construct($client, $action, $response) {
		$this->response = $response;
		
		foreach($response->response() as $item) {
			$this->items[] = new ResourceInstance($client, $action, $item);
		}
	}
	
	/**
	 * @return int object count
	 */
	public function count() {
		return count($this->items);
	}
	
	/**
	 * @return Response
	 */
	public function apiResponse() {
		return $this->response;
	}
	
	/**
	 * @return ResourceInstance first object
	 */
	public function first() {
		return $this->items[0];
	}
	
	/**
	 * @return ResourceInstance last object
	 */
	public function last() {
		return $this->items[ $this->count() - 1 ];
	}
	
	/**
	 * Returns all objects in an array.
	 * @return array
	 */
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

/**
 * Response from the API.
 */
class Response implements \ArrayAccess {
	private $action;
	private $envelope;
	
	/**
	 * @param Action $action
	 * @param \Httpful\Response envelope received response
	 */
	public function __construct($action, $response) {
		if($response->code == 401)
			throw new AuthenticationFailed($response->body->message);
		
		$this->action = $action;
		$this->envelope = $response->body;
	}
	
	/**
	 * @return boolean
	 */
	public function isOk() {
		return $this->envelope->status;
	}
	
	/**
	 * @return string
	 */
	public function message() {
		return $this->envelope->message;
	}
	
	/**
	 * For known layouts, namespaced response is returned, or else the data is returned as is.
	 * @return \stdClass
	 */
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
	
	/**
	 * @return \stdClass
	 */
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

/**
 * A client for a HaveAPI based API.
 */
class Client extends Resource {
	private $uri;
	private $version;
	private $identity;
	private $authProvider;
	private $queryParams;
	private $descCallback = null;
	private static $authProviders = array();
	
	/**
	 * Register authentication provider with $name and implementation in $class.
	 * @param string $name name of authentication method (has to match with names in API)
	 * @param string $class name of a class
	 * @param boolean $force replace the provider if it already exists
	 */
	public static function registerAuthProvider($name, $class, $force = true) {
		if(!$force && in_array($name, self::$authProviders))
			return;
		
		self::$authProviders[$name] = $class;
	}
	
	/**
	 * @param string $uri URL to the API root, do not specify version here
	 * @param mixed $version API version to use, defaults to default version
	 * @param string $identity string to be sent in User-Agent in every request
	 */
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
	
	/**
	 * Fetch the API description if it isn't fetched yet.
	 * @param boolean $force fetch even it is already fetched
	 */
	public function setup($force = false) {
		if(!$force && $this->description)
			return;
		
		$this->description = $this->fetchDescription();
		
		if($this->descCallback)
			call_user_func($this->descCallback, $this);
	}
	
	/**
	 * Return the API description.
	 * @return \stdClass may be NULL if the client is not set up yet
	 */
	public function getDescription() {
		return $this->description;
	}
	
	/**
	 * Set the description to $desc. The client will use this description
	 * and will not ask the API about it.
	 * @param \stdClass $desc
	 */
	public function setDescription($desc) {
		$this->description = $desc;
	}
	
	/**
	 * Register a callback function that will be called when the description
	 * is changed. The function is passed instance of Client as an argument.
	 * @param callable $fn
	 */
	public function registerDescriptionChangeFunc($fn) {
		$this->descCallback = $fn;
	}
	
	/**
	 * Authenticate with $method and options $opts.
	 * @param string $method authentication provider name
	 * @param array $opts options passed to the provider
	 * @param boolean $forceSetup force reloading the description of the API
	 */
	public function authenticate($method, $opts, $forceSetup = true) {
		if(!array_key_exists($method, self::$authProviders))
			throw new AuthenticationFailed("Auth method '$method' is not registered");
		
		$this->setup();
		
		$this->authProvider = new self::$authProviders[$method]($this, $this->description->authentication->{$method}, $opts);
		
		$this->setup($forceSetup);
	}
	
	/**
	 * Return the authentication provider.
	 * @return AuthProvider
	 */
	public function getAuthenticationProvider() {
		return $this->authProvider;
	}
	
	/**
	 * Invoke action $action with $params and interpret the response.
	 * @param Action $action
	 * @param array $params
	 * @return mixed response
	 */
	public function call($action, $params = array()) {
		$response = new Response($action, $this->directCall($action, $params));
		
		if(!$response->isOk()) {
			throw new ActionFailed($response, "Action '".$action->name()."' failed: ".$response->message());
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
	
	/**
	 * Invoke action $action with $params and do notinterpret the response.
	 * @param Action $action
	 * @param array $params
	 * @return mixed response
	 */
	public function directCall($action, $params = array()) {
		$fn = strtolower($action->httpMethod());
		
// 		echo "execute {$action->httpMethod()} {$action->url()}\n<br>\n";
		
		$request = $this->getRequest($fn, $this->uri . $action->url());
		
		if(!$this->sendAsQueryParams($fn))
			$request->body(empty($params) ? '{}' : json_encode(array($action->getNamespace('input') => $params)));
		
		$this->authProvider->authenticate($request);
		
		return $this->sendRequest($request, $action, $params);
	}
	
	/**
	 * Create \Httpful\Request instance.
	 * @param string $method HTTP method
	 * @param string $url
	 */
	protected function getRequest($method, $url) {
		$this->queryParams = array();
		
		$request = \Httpful\Request::$method($url);
		$request->sendsJson();
		$request->expectsJson();
		$request->addHeader('User-Agent', $this->identity);
		
		return $request;
	}
	
	/**
	 * Send \Httpful\Request.
	 * @param \Httpful\Request $request
	 * @param Action $action
	 * @param array $params
	 */
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
	
	/**
	 * @param string $method
	 * @return boolean true for HTTP methods GET and OPTIONS.
	 */
	protected function sendAsQueryParams($method) {
		return in_array(strtolower($method), array('get', 'options'));
	}
	
	/**
	 * Fetch the description.
	 * @return \stdClass
	 */
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
