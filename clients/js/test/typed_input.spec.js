const { expect } = require('chai');
const server = require('./helpers/server');
const HaveAPI = require('../dist/haveapi-client.js');

function setup(client) {
  return new Promise((resolve, reject) => {
    client.setup((c, status) => {
      if (status) {
        resolve();
      } else {
        reject(new Error('setup failed'));
      }
    });
  });
}

function authenticateBasic(client) {
  return new Promise((resolve, reject) => {
    client.authenticate('basic', { user: 'user', password: 'pass' }, (c, status) => {
      if (status) {
        resolve();
      } else {
        reject(new Error('authentication failed'));
      }
    });
  });
}

function invoke(actionFn, params) {
  return new Promise((resolve, reject) => {
    if (typeof actionFn !== 'function') {
      reject(new Error('action is not callable'));
      return;
    }

    actionFn(params, (c, reply) => resolve(reply));
  });
}

function echoParams(overrides) {
  const base = {
    i: 1,
    f: 1.5,
    b: true,
    dt: '2020-01-01T00:00:00Z',
    s: 'ok',
    t: 'ok'
  };

  if (!overrides) {
    return base;
  }

  return Object.assign({}, base, overrides);
}

describe('HaveAPI JS client typed input', function () {
  this.timeout(5000);

  let baseUrl;
  let client;

  before(async () => {
    const started = await server.start();
    baseUrl = started.baseUrl;
  });

  after(async () => {
    await server.stop();
  });

  beforeEach(async () => {
    await server.reset(baseUrl);
    client = new HaveAPI.Client(baseUrl);
  });

  it('coerces valid values for scalar types', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, {
      i: ' 42 ',
      f: 5,
      b: 'yes',
      dt: '2020-01-01T00:00:00Z',
      s: 123,
      t: false
    });

    expect(reply.isOk()).to.equal(true);
    const response = reply.response();
    expect(response.i).to.equal(42);
    expect(response.f).to.equal(5);
    expect(response.b).to.equal(true);
    expect(response.dt).to.be.a('string');
    expect(response.s).to.equal('123');
    expect(response.t).to.equal('false');
  });

  it('accepts exponent floats', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ f: '1e3' }));

    expect(reply.isOk()).to.equal(true);
    expect(reply.response().f).to.equal(1000);
  });

  it('rejects invalid integers', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ i: 'abc' }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.message()).to.equal('invalid input parameters');
    expect(reply.envelope.errors).to.have.property('i');
    expect(reply.envelope.errors.i.join(' ')).to.match(/not a valid integer/);
  });

  it('rejects non-integral numbers as integers', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ i: 12.3 }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('i');
    expect(reply.envelope.errors.i.join(' ')).to.match(/not a valid integer/);
  });

  it('rejects invalid floats', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ f: 'abc' }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('f');
    expect(reply.envelope.errors.f.join(' ')).to.match(/not a valid float/);
  });

  it('rejects invalid booleans', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ b: 'maybe' }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('b');
    expect(reply.envelope.errors.b.join(' ')).to.match(/not a valid boolean/);

    const replyNumber = await invoke(client.test.echo, echoParams({ b: 2 }));
    expect(replyNumber.isOk()).to.equal(false);
    expect(replyNumber.envelope.errors).to.have.property('b');
    expect(replyNumber.envelope.errors.b.join(' ')).to.match(/not a valid boolean/);
  });

  it('coerces boolean string tokens', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ b: '1' }));

    expect(reply.isOk()).to.equal(true);
    expect(reply.response().b).to.equal(true);
  });

  it('rejects non-ISO datetimes', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ dt: 'yesterday' }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('dt');
    expect(reply.envelope.errors.dt.join(' ')).to.match(/ISO 8601/);
  });

  it('rejects invalid calendar dates', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo, echoParams({ dt: '2020-02-30' }));

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('dt');
    expect(reply.envelope.errors.dt.join(' ')).to.match(/ISO 8601/);
  });

  it('rejects arrays and objects for string/text', async () => {
    await setup(client);
    const replyArray = await invoke(client.test.echo, echoParams({ s: [1, 2] }));

    expect(replyArray.isOk()).to.equal(false);
    expect(replyArray.envelope.errors).to.have.property('s');
    expect(replyArray.envelope.errors.s.join(' ')).to.match(/not a valid string/);

    const replyObject = await invoke(client.test.echo, echoParams({ t: { a: 1 } }));
    expect(replyObject.isOk()).to.equal(false);
    expect(replyObject.envelope.errors).to.have.property('t');
    expect(replyObject.envelope.errors.t.join(' ')).to.match(/not a valid string/);
  });

  it('coerces resource ids from numbers and strings', async () => {
    await setup(client);
    const replyNumber = await invoke(client.test.echo_resource, { project: 1 });

    expect(replyNumber.isOk()).to.equal(true);
    expect(replyNumber.response().project).to.equal(1);

    const replyString = await invoke(client.test.echo_resource, { project: '1' });
    expect(replyString.isOk()).to.equal(true);
    expect(replyString.response().project).to.equal(1);
  });

  it('coerces resource instances to ids', async () => {
    await setup(client);
    await authenticateBasic(client);

    const projects = await invoke(client.project.list, {});
    const project = projects.first();

    expect(project).to.not.equal(null);

    const reply = await invoke(client.test.echo_resource, { project: project });
    expect(reply.isOk()).to.equal(true);
    expect(reply.response().project).to.equal(project.id);
  });

  it('rejects invalid resource ids', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo_resource, { project: 'abc' });

    expect(reply.isOk()).to.equal(false);
    expect(reply.envelope.errors).to.have.property('project');
    expect(reply.envelope.errors.project.join(' ')).to.match(/not a valid resource id/);
  });

  it('accepts null for optional resource params', async () => {
    await setup(client);
    const reply = await invoke(client.test.echo_resource_optional, { project: null });

    expect(reply.isOk()).to.equal(true);
    expect(reply.response().project_provided).to.equal(true);
    expect(reply.response().project_nil).to.equal(true);
  });
});
