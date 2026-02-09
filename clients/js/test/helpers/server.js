const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

const READY_PREFIX = 'HAVEAPI_TEST_SERVER_READY';

let child = null;
let baseUrl = null;

function start() {
  if (baseUrl) {
    return Promise.resolve({ baseUrl });
  }

  const root = path.resolve(__dirname, '..', '..', '..', '..');
  const script = path.join(root, 'servers', 'ruby', 'test_support', 'client_test_server.rb');
  const gemfile = path.join(root, 'servers', 'ruby', 'Gemfile');
  const cwd = path.resolve(__dirname, '..', '..');

  return new Promise((resolve, reject) => {
    const env = Object.assign({}, process.env, { BUNDLE_GEMFILE: gemfile });
    child = spawn('bundle', ['exec', 'ruby', script, '--port', '0'], {
      cwd,
      env,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let buffer = '';
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error('test server did not start in time'));
    }, 10000);
    const onData = (data) => {
      buffer += data.toString();
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop();

      for (const line of lines) {
        if (line.includes(READY_PREFIX)) {
          const parts = line.trim().split(/\s+/);
          baseUrl = parts[parts.length - 1];
          waitForHealth(baseUrl)
            .then(() => {
              cleanup();
              resolve({ baseUrl });
            })
            .catch((err) => {
              cleanup();
              reject(err);
            });
          return;
        }
      }
    };

    const onExit = (code) => {
      cleanup();
      reject(new Error(`test server exited before ready (${code})`));
    };

    const cleanup = () => {
      clearTimeout(timeout);
      if (!child) {
        return;
      }

      child.stdout.off('data', onData);
      child.stderr.off('data', onData);
      child.off('exit', onExit);
    };

    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.on('exit', onExit);
  });
}

function reset(url) {
  const target = new URL('/__reset', url);

  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        method: 'POST',
        hostname: target.hostname,
        port: target.port,
        path: target.pathname,
        headers: {
          'Content-Type': 'application/json'
        }
      },
      (res) => {
        res.resume();
        if (res.statusCode !== 200) {
          reject(new Error(`reset failed: ${res.statusCode}`));
        } else {
          resolve();
        }
      }
    );

    req.on('error', reject);
    req.write('{}');
    req.end();
  });
}

function stop() {
  if (!child) {
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    const proc = child;
    child = null;
    baseUrl = null;

    proc.once('exit', () => resolve());
    proc.kill('SIGTERM');

    setTimeout(() => {
      try {
        proc.kill('SIGKILL');
      } catch (err) {
        resolve();
      }
    }, 2000).unref();
  });
}

module.exports = {
  start,
  reset,
  stop
};

function waitForHealth(url) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 5000;

    const attempt = () => {
      const target = new URL('/__health', url);
      const req = http.request(
        {
          method: 'GET',
          hostname: target.hostname,
          port: target.port,
          path: target.pathname
        },
        (res) => {
          res.resume();
          if (res.statusCode === 200) {
            resolve();
          } else {
            retry();
          }
        }
      );

      req.on('error', retry);
      req.end();
    };

    const retry = () => {
      if (Date.now() > deadline) {
        reject(new Error('test server did not become healthy in time'));
        return;
      }

      setTimeout(attempt, 50);
    };

    attempt();
  });
}
