const { expect } = require('chai');
const server = require('../helpers/server');
const CallbackAdapter = require('../helpers/adapter_callback');

describe('HaveAPI JS client contract', function () {
  this.timeout(5000);

  let baseUrl;
  let adapter;

  before(async () => {
    const started = await server.start();
    baseUrl = started.baseUrl;
  });

  after(async () => {
    await server.stop();
  });

  beforeEach(async () => {
    await server.reset(baseUrl);
    adapter = new CallbackAdapter(baseUrl);
  });

  it('setup without auth hides protected resources', async () => {
    await adapter.setup();
    expect(adapter.hasProjectResource()).to.equal(false);
  });

  it('basic auth allows listing and creating projects', async () => {
    await adapter.authenticateBasic('user', 'pass');
    expect(adapter.hasProjectResource()).to.equal(true);

    const projects = await adapter.listProjects();
    expect(projects.length).to.be.at.least(2);

    const created = await adapter.createProject('Gamma');
    expect(created.name).to.equal('Gamma');
  });

  it('token auth allows using existing token', async () => {
    const token = await adapter.authenticateToken({ user: 'user', pass: 'pass' });

    const tokenAdapter = new CallbackAdapter(baseUrl);
    await tokenAdapter.useToken(token);

    const projects = await tokenAdapter.listProjects();
    expect(projects.length).to.be.at.least(2);
  });

  it('handles nested tasks', async () => {
    await adapter.authenticateBasic('user', 'pass');

    const projects = await adapter.listProjects();
    const project = projects.first();

    const task = await adapter.createTask(project.id, 'alpha');
    expect(task.label).to.equal('alpha');

    const tasks = await adapter.listTasks(project.id);
    expect(tasks.length).to.be.at.least(1);
  });

  it('runs blocking actions and reports progress', async () => {
    await adapter.authenticateBasic('user', 'pass');

    const projects = await adapter.listProjects();
    const project = projects.first();
    const task = await adapter.createTask(project.id, 'runner');

    const result = await adapter.runTaskBlocking(project.id, task.id);

    expect(result.onReplyCalled).to.equal(true);
    expect(result.onDoneCalled).to.equal(true);
    expect(result.progress.length).to.be.at.least(1);
    expect(result.progress[result.progress.length - 1]).to.be.at.least(result.progress[0]);
  });

  it('reports forced failures', async () => {
    await adapter.setup();

    let failed = false;
    try {
      await adapter.failAction();
    } catch (err) {
      failed = true;
      expect(err).to.have.property('isOk');
      expect(err.isOk()).to.equal(false);
    }

    expect(failed).to.equal(true);
  });
});
