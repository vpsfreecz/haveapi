const HaveAPI = require('../../dist/haveapi-client.js');

class CallbackAdapter {
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
    this.client = new HaveAPI.Client(baseUrl);
  }

  setup() {
    return new Promise((resolve, reject) => {
      this.client.setup((c, status) => {
        if (status) {
          resolve();
        } else {
          reject(new Error('setup failed'));
        }
      });
    });
  }

  hasProjectResource() {
    return !!this.client.project;
  }

  authenticateBasic(user, pass) {
    return this._authenticate('basic', { user, password: pass });
  }

  authenticateToken(opts) {
    return this._authenticate('token', { user: opts.user, password: opts.pass })
      .then(() => this.client.authProvider.token);
  }

  useToken(token) {
    this.client = new HaveAPI.Client(this.baseUrl);
    return this._authenticate('token', { token });
  }

  listProjects() {
    return this._invoke(this.client.project.list, [], null);
  }

  createProject(name) {
    return this._invoke(this.client.project.create, [], { name });
  }

  listTasks(projectId) {
    return this._invoke(this.client.project.task.list, [projectId], null);
  }

  createTask(projectId, label) {
    return this._invoke(this.client.project.task.create, [projectId], { label });
  }

  runTaskBlocking(projectId, taskId) {
    return new Promise((resolve, reject) => {
      let onReplyCalled = false;
      let onDoneCalled = false;
      const progress = [];

      this.client.project.task.run(projectId, taskId, {
        onReply: (c, reply) => {
          onReplyCalled = true;
          if (reply && reply.isOk && !reply.isOk()) {
            reject(reply);
          }
        },
        onStateChange: (c, reply, state) => {
          progress.push(state.progress.current);
        },
        onDone: (c, reply) => {
          onDoneCalled = true;
          resolve({ onReplyCalled, onDoneCalled, progress });
        }
      });
    });
  }

  failAction() {
    return this._invoke(this.client.test.fail, [], null);
  }

  _authenticate(method, opts) {
    return new Promise((resolve, reject) => {
      this.client.authenticate(method, opts, (c, status) => {
        if (status) {
          resolve();
        } else {
          reject(new Error(`authentication failed: ${method}`));
        }
      });
    });
  }

  _invoke(action, pathArgs, params) {
    return new Promise((resolve, reject) => {
      if (typeof action !== 'function') {
        reject(new Error('action is not callable'));
        return;
      }

      const args = Array.isArray(pathArgs) ? pathArgs.slice() : [];
      const opts = { onReply: (c, reply) => {
        if (reply && reply.isOk && !reply.isOk()) {
          reject(reply);
          return;
        }
        resolve(reply);
      }};

      if (params) {
        opts.params = params;
      }

      args.push(opts);
      action(...args);
    });
  }
}

module.exports = CallbackAdapter;
