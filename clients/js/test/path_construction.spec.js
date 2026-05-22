const { expect } = require('chai');

function loadHaveAPI() {
  delete require.cache[require.resolve('../dist/haveapi-client.js')];
  return require('../dist/haveapi-client.js');
}

function makeClient(HaveAPI, url = 'https://api.example') {
  const client = new HaveAPI.Client(url, {});

  client.apiSettings = { meta: { namespace: '_meta' } };
  client.authProvider = {
    credentials() {
      return undefined;
    },
    headers() {
      return {};
    },
    queryParameters() {
      return {};
    }
  };

  return client;
}

function makeAction(HaveAPI, client, path = '/v1/users/{user_id}') {
  return new HaveAPI.Client.Action(
    client,
    {
      _private: { name: 'user' },
      defaultParams() {
        return {};
      }
    },
    'show',
    {
      aliases: [],
      blocking: false,
      method: 'GET',
      path,
      input: {
        layout: 'hash',
        namespace: 'user',
        parameters: {}
      },
      output: {
        layout: 'hash',
        namespace: 'user',
        parameters: {}
      }
    },
    []
  );
}

describe('HaveAPI JS client path construction', () => {
  it('encodes caller-supplied path arguments', () => {
    const HaveAPI = loadHaveAPI();
    const client = makeClient(HaveAPI);
    const capturedUrls = [];

    client._private.http.request = (opts) => {
      capturedUrls.push(opts.url);
      opts.callback(200, {
        status: true,
        response: { user: {}, _meta: {} },
        message: null,
        errors: null
      });
    };

    const action = makeAction(HaveAPI, client);
    const attackerPathArg = '42?user[name]=alice&_meta[includes]=group__secret';

    action.directInvoke(attackerPathArg, { onReply() {} });

    expect(capturedUrls).to.deep.equal([
      'https://api.example/v1/users/42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret'
    ]);

    const parsed = new URL(capturedUrls[0]);
    expect(parsed.pathname).to.equal('/v1/users/42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret');
    expect(parsed.search).to.equal('');
  });

  it('encodes API-provided path arguments', () => {
    const HaveAPI = loadHaveAPI();
    const client = makeClient(HaveAPI);
    const capturedUrls = [];

    client._private.http.request = (opts) => {
      capturedUrls.push(opts.url);
      opts.callback(200, {
        status: true,
        response: { user: {}, _meta: {} },
        message: null,
        errors: null
      });
    };

    const action = makeAction(HaveAPI, client);
    const attackerPathArg = '42?user[name]=alice&_meta[includes]=group__secret';

    action.provideIdArgs([attackerPathArg]);
    action.directInvoke({ onReply() {} });

    expect(capturedUrls).to.deep.equal([
      'https://api.example/v1/users/42%3Fuser%5Bname%5D%3Dalice%26_meta%5Bincludes%5D%3Dgroup__secret'
    ]);

    const parsed = new URL(capturedUrls[0]);
    expect(parsed.search).to.equal('');
  });

  it('clears invocation path state when the transport throws', () => {
    const HaveAPI = loadHaveAPI();
    const client = makeClient(HaveAPI);
    const capturedUrls = [];
    let failNext = true;

    client._private.http.request = (opts) => {
      capturedUrls.push(opts.url);

      if (failNext) {
        failNext = false;
        throw new Error('simulated transport failure');
      }

      opts.callback(200, {
        status: true,
        response: { user: {}, _meta: {} },
        message: null,
        errors: null
      });
    };

    const action = makeAction(HaveAPI, client);

    expect(() => action.directInvoke(42, { onReply() {} }))
      .to.throw('simulated transport failure');
    expect(action.preparedPath).to.equal(null);

    let unresolved = null;
    const oldLog = console.log;

    console.log = () => {};

    try {
      action.directInvoke({ onReply() {} });
    } catch (err) {
      unresolved = err;
    } finally {
      console.log = oldLog;
    }

    expect(unresolved).to.have.property('name', 'UnresolvedArguments');
    expect(capturedUrls).to.deep.equal([
      'https://api.example/v1/users/42'
    ]);
  });

  it('preserves configured API base paths when resolving action paths', () => {
    const HaveAPI = loadHaveAPI();
    const client = makeClient(HaveAPI, 'https://api.example/api');
    const capturedUrls = [];

    client._private.http.request = (opts) => {
      capturedUrls.push(opts.url);
      opts.callback(200, {
        status: true,
        response: { user: {}, _meta: {} },
        message: null,
        errors: null
      });
    };

    const action = makeAction(HaveAPI, client);

    action.directInvoke(42, { onReply() {} });

    expect(capturedUrls).to.deep.equal([
      'https://api.example/api/v1/users/42'
    ]);
  });

  it('rejects description-controlled action paths that can switch authority', () => {
    const HaveAPI = loadHaveAPI();
    const unsafePaths = [
      '@127.0.0.1:8080/internal-metadata',
      '//attacker.example/internal-metadata',
      'https://attacker.example/internal-metadata',
      '/v1/users\\..\\tokens',
      '/v1/users/@attacker'
    ];

    unsafePaths.forEach((unsafePath) => {
      const client = makeClient(HaveAPI);
      const reads = {
        credentials: 0,
        headers: 0,
        queryParameters: 0,
        requests: 0
      };

      client.authProvider = {
        credentials() {
          reads.credentials += 1;
          return undefined;
        },
        headers() {
          reads.headers += 1;
          return { 'X-HaveAPI-OAuth2-Token': 'secret-token' };
        },
        queryParameters() {
          reads.queryParameters += 1;
          return {};
        }
      };
      client._private.http.request = () => {
        reads.requests += 1;
      };

      const action = makeAction(HaveAPI, client, unsafePath);

      expect(() => action.directInvoke({ onReply() {} }))
        .to.throw(HaveAPI.Client.Exceptions.ProtocolError);
      expect(reads).to.deep.equal({
        credentials: 0,
        headers: 0,
        queryParameters: 0,
        requests: 0
      });
    });
  });
});
