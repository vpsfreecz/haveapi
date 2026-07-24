const { expect } = require('chai');

function loadHaveAPI() {
  delete require.cache[require.resolve('../dist/haveapi-client.js')];
  return require('../dist/haveapi-client.js');
}

function emptyResource(actions, resources) {
  return {
    resources: resources || {},
    actions: actions || {}
  };
}

function actionWithAliases(aliases) {
  return {
    aliases,
    blocking: false,
    method: 'GET',
    path: '/v1/widgets',
    input: null,
    output: null
  };
}

function showAction(parameters) {
  return {
    aliases: [],
    blocking: false,
    method: 'GET',
    path: '/v1/unsafe/{unsafe_id}',
    input: {
      layout: 'object',
      namespace: 'unsafe',
      parameters: {}
    },
    output: {
      layout: 'object',
      namespace: 'unsafe',
      parameters
    },
    meta: {}
  };
}

function apiDescription(resources) {
  return {
    authentication: {},
    meta: { namespace: '_meta' },
    resources
  };
}

function newClient(HaveAPI) {
  return new HaveAPI.Client('https://api.example', {});
}

function resourceMap() {
  return Object.create(null);
}

describe('HaveAPI JS client description member attachment', () => {
  it('keeps direct access for safe resource, action, and alias names', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);
    const childResources = resourceMap();

    childResources.comments = emptyResource();

    client.useDescription(apiDescription({
      widgets: emptyResource({
        list: actionWithAliases(['index'])
      }, childResources)
    }));

    expect(client.resources).to.have.length(1);
    expect(client.widgets).to.be.a('function');
    expect(client.widgets.resources).to.have.length(1);
    expect(client.widgets.comments).to.be.a('function');
    expect(client.widgets.actions).to.deep.equal(['list']);
    expect(client.widgets.list).to.be.a('function');
    expect(client.widgets.index).to.equal(client.widgets.list);
  });

  it('does not let top-level resource names clobber client internals', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);
    const resources = resourceMap();

    resources.resources = emptyResource();
    resources._private = emptyResource();
    resources.setup = emptyResource();
    resources.widgets = emptyResource();
    resources['__proto__'] = emptyResource();

    expect(() => client.useDescription(apiDescription(resources))).not.to.throw();

    expect(client.resources.map((resource) => resource.getName()))
      .to.deep.equal(['resources', '_private', 'setup', 'widgets', '__proto__']);
    expect(client.resources).to.be.an('array');
    expect(client._private).to.be.an('object');
    expect(client.setup).to.be.a('function');
    expect(client.widgets).to.be.a('function');

    expect(() => client.destroyResources()).not.to.throw();
    expect(client.resources).to.deep.equal([]);
    expect(client._private).to.be.an('object');
    expect(client.setup).to.be.a('function');
  });

  it('does not let nested resource names or action aliases clobber resource internals', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);
    const childResources = resourceMap();

    childResources.resources = emptyResource();
    childResources.actions = emptyResource();
    childResources.tasks = emptyResource();
    childResources['__proto__'] = emptyResource();

    client.useDescription(apiDescription({
      widgets: emptyResource({
        show: actionWithAliases(['actions', 'resources', '_private', '__proto__', 'safeAlias']),
        actions: actionWithAliases(['run'])
      }, childResources)
    }));

    const widgets = client.widgets;

    expect(widgets.resources.map((resource) => resource.getName()))
      .to.deep.equal(['resources', 'actions', 'tasks', '__proto__']);
    expect(widgets.resources).to.be.an('array');
    expect(widgets.actions).to.deep.equal(['show', 'actions']);
    expect(widgets._private).to.be.an('object');
    expect(widgets.getName()).to.equal('widgets');
    expect(widgets.tasks).to.be.a('function');
    expect(widgets.show).to.be.a('function');
    expect(widgets.safeAlias).to.equal(widgets.show);
    expect(widgets.run).to.be.a('function');
  });

  it('ignores inherited description keys while attaching resources and actions', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);
    const inheritedActions = { inherited: actionWithAliases([]) };
    const actions = Object.create(inheritedActions);
    const inheritedResources = { inherited: emptyResource() };
    const resources = Object.create(inheritedResources);

    actions.list = actionWithAliases([]);
    resources.widgets = emptyResource(actions);

    client.useDescription(apiDescription(resources));

    expect(client.resources.map((resource) => resource.getName()))
      .to.deep.equal(['widgets']);
    expect(client.inherited).to.equal(undefined);
    expect(client.widgets.actions).to.deep.equal(['list']);
    expect(client.widgets.inherited).to.equal(undefined);
  });

  it('finds top-level and nested resources that cannot be attached directly', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);
    const childResources = resourceMap();

    childResources.resources = emptyResource({
      show: showAction({id: {type: 'Integer'}})
    });

    client.useDescription(apiDescription({
      setup: emptyResource({
        show: showAction({id: {type: 'Integer'}})
      }),
      widgets: emptyResource({}, childResources)
    }));

    expect(HaveAPI.Client.findResource(client, ['setup']).getName()).to.equal('setup');
    expect(
      HaveAPI.Client.findResource(client, ['widgets', 'resources']).getName()
    ).to.equal('resources');
  });

  it('materializes an association to a resource with an unsafe direct name', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);

    client.useDescription(apiDescription({
      setup: emptyResource({
        show: showAction({id: {type: 'Integer'}})
      })
    }));

    const owner = {
      _private: {
        client,
        attributes: {
          target: {
            id: 1,
            _meta: {
              resolved: true,
              path_params: [1]
            }
          }
        }
      }
    };

    const association = HaveAPI.Client.ResourceInstance.prototype.resolveAssociation.call(
      owner,
      'target',
      ['setup']
    );

    expect(association).to.be.an.instanceof(HaveAPI.Client.ResourceInstance);
    expect(association.id).to.equal(1);
  });

  it('reports an invalid association resource path as a protocol error', () => {
    const HaveAPI = loadHaveAPI();
    const client = newClient(HaveAPI);

    client.useDescription(apiDescription({}));

    expect(() => HaveAPI.Client.findResource(client, ['missing']))
      .to.throw(
        HaveAPI.Client.Exceptions.ProtocolError,
        "Associated resource 'missing' not found"
      );
  });
});
