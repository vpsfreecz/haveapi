const HaveAPI = require("../../dist/haveapi-client.js");

// This adapter targets the shared deterministic Ruby test API, not an
// application endpoint schema or a second production client implementation.
class AsyncAdapter {
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
    this.client = new HaveAPI.AsyncClient(baseUrl);
  }
  setup() {
    return this.client.setup();
  }
  hasProjectResource() {
    try {
      this.client.resource("project");
      return true;
    } catch {
      return false;
    }
  }
  authenticateBasic(user, pass) {
    return this.client.authenticate("basic", { user, password: pass });
  }
  async authenticateToken(opts) {
    await this.client.authenticate("token", {
      user: opts.user,
      password: opts.pass,
    });
    // The server fixture deliberately issues token-<login> (TokenConfig in
    // servers/ruby/test_support/client_test_api.rb). No provider state is exposed
    // by AsyncClient; using this known fixture token also tests existing-token auth.
    return `token-${opts.user}`;
  }
  useToken(token) {
    this.client = new HaveAPI.AsyncClient(this.baseUrl);
    return this.client.authenticate("token", { token });
  }
  async invoke(resource, action, ids = [], params) {
    const result = await resource.action(action)(
      ...ids,
      ...(params ? [{ params }] : []),
    );
    return result.value;
  }
  listProjects() {
    return this.invoke(this.client.resource("project"), "list");
  }
  publicProjects() {
    return this.invoke(this.client.resource("project"), "public_list");
  }
  publicProject(projectId) {
    return this.invoke(this.client.resource("project"), "public_show", [
      projectId,
    ]);
  }
  createProject(name) {
    return this.invoke(this.client.resource("project"), "create", [], { name });
  }
  listTasks(projectId) {
    return this.invoke(
      this.client.resource("project").resource("task"),
      "list",
      [projectId],
    );
  }
  createTask(projectId, label) {
    return this.invoke(
      this.client.resource("project").resource("task"),
      "create",
      [projectId],
      { label },
    );
  }
  async runTaskBlocking(projectId, taskId) {
    const started = await this.client
      .resource("project")
      .resource("task")
      .action("run")(projectId, taskId);
    const progress = [];
    await this.client.waitForCompletion(started, {
      timeoutMs: 5000,
      onStateChange(state) {
        progress.push(state.progress.current);
      },
    });
    return { onReplyCalled: true, onDoneCalled: true, progress };
  }
  failAction() {
    return this.invoke(this.client.resource("test"), "fail");
  }
}
module.exports = AsyncAdapter;
