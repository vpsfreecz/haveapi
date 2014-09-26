<?php

namespace HaveAPI\Client;

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
				throw new Exception\ActionFailed($ret, "Action '".$action->name()."' failed: ".$ret->message());
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
