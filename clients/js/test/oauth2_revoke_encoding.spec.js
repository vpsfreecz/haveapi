const { expect } = require('chai');

function loadHaveAPIWithXMLHttpRequest(XMLHttpRequest) {
  const modulePath = require.resolve('../dist/haveapi-client.js');
  const oldWindow = global.window;

  delete require.cache[modulePath];
  global.window = { XMLHttpRequest };

  const HaveAPI = require(modulePath);

  if (oldWindow === undefined) {
    delete global.window;
  } else {
    global.window = oldWindow;
  }

  delete require.cache[modulePath];
  return HaveAPI;
}

describe('HaveAPI JS client OAuth2 revoke encoding', () => {
  function makeOAuth2(HaveAPI, revokeUrl, token = 'access-token') {
    const client = new HaveAPI.Client('https://api.example', {});

    return new HaveAPI.Client.Authentication.OAuth2(
      client,
      { access_token: { access_token: token } },
      {
        http_header: 'X-HaveAPI-OAuth2-Token',
        revoke_url: revokeUrl
      }
    );
  }

  it('encodes OAuth2 revoke form tokens', () => {
    let capturedBody = null;
    let capturedContentType = null;

    function FakeXMLHttpRequest() {
      this.headers = {};
      this.readyState = 0;
      this.status = 200;
    }

    FakeXMLHttpRequest.prototype.open = function open(method, url) {
      this.method = method;
      this.url = url;
    };

    FakeXMLHttpRequest.prototype.setRequestHeader = function setRequestHeader(name, value) {
      this.headers[name] = value;

      if (name.toLowerCase() === 'content-type') {
        capturedContentType = value;
      }
    };

    FakeXMLHttpRequest.prototype.send = function send(body) {
      capturedBody = body;
      this.readyState = 4;
      this.onreadystatechange();
    };

    const HaveAPI = loadHaveAPIWithXMLHttpRequest(FakeXMLHttpRequest);
    const token = 'abc+def&token_type_hint=refresh_token=%25 space';
    const auth = makeOAuth2(HaveAPI, 'https://api.example/_auth/oauth2/revoke', token);

    auth.setup();
    auth.logout(() => {});

    expect(capturedContentType).to.equal('application/x-www-form-urlencoded');
    expect(capturedBody).to.equal(`token=${encodeURIComponent(token)}`);

    const parsed = new URLSearchParams(capturedBody);
    expect(parsed.get('token')).to.equal(token);
    expect(parsed.has('token_type_hint')).to.equal(false);
  });

  it('resolves same-origin relative OAuth2 revoke URLs against the API origin', () => {
    let capturedUrl = null;

    function FakeXMLHttpRequest() {
      this.headers = {};
      this.readyState = 0;
      this.status = 200;
    }

    FakeXMLHttpRequest.prototype.open = function open(method, url) {
      this.method = method;
      capturedUrl = url;
    };

    FakeXMLHttpRequest.prototype.setRequestHeader = function setRequestHeader() {};

    FakeXMLHttpRequest.prototype.send = function send() {
      this.readyState = 4;
      this.onreadystatechange();
    };

    const HaveAPI = loadHaveAPIWithXMLHttpRequest(FakeXMLHttpRequest);
    const auth = makeOAuth2(HaveAPI, '/_auth/oauth2/revoke');

    auth.setup();
    auth.logout(() => {});

    expect(capturedUrl).to.equal('https://api.example/_auth/oauth2/revoke');
  });

  it('rejects cross-origin OAuth2 revoke URLs before sending tokens', () => {
    let openedUrl = null;
    let sentBody = null;
    let callbackCalled = false;

    function FakeXMLHttpRequest() {
      this.headers = {};
      this.readyState = 0;
      this.status = 200;
    }

    FakeXMLHttpRequest.prototype.open = function open(method, url) {
      openedUrl = url;
    };

    FakeXMLHttpRequest.prototype.setRequestHeader = function setRequestHeader() {};

    FakeXMLHttpRequest.prototype.send = function send(body) {
      sentBody = body;
      this.readyState = 4;
      this.onreadystatechange();
    };

    const HaveAPI = loadHaveAPIWithXMLHttpRequest(FakeXMLHttpRequest);
    const auth = makeOAuth2(
      HaveAPI,
      'https://attacker.example/collect-token',
      'vuln78-secret-access-token'
    );

    auth.setup();

    expect(() => auth.logout(() => { callbackCalled = true; }))
      .to.throw(HaveAPI.Client.Exceptions.ProtocolError);
    expect(openedUrl).to.equal(null);
    expect(sentBody).to.equal(null);
    expect(callbackCalled).to.equal(false);
  });
});
