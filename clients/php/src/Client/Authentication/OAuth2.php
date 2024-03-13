<?php

namespace HaveAPI\Client\Authentication;

/**
 * Provider for OAuth2 authentication.
 *
 * This provider allows the developer to request authorization code by redirecting
 * the user to the authorization endpoint and then to request the access token.
 * The provider relies on sessions and directly interacts with them. It is up to
 * the developer to ensure sessions are configured.
 *
 * Required options are: `client_id`, `client_secret` and `redirect_uri`. Existing
 * access token can be passed as option `access_token`, note that it has to
 * conform to the format returned by jsonSerialize(). Other OAuth2 parameters
 * are read from HaveAPI description.
 */
class OAuth2 extends Base
{
    private $genericProvider;

    private $accessToken;

    public function setup()
    {
        $apiUri = $this->client->getUri();

        if (isset($this->opts['client_id'])) {
            $headers = [
                'User-Agent' => $this->client->getIdentity(),
            ];

            $ip = $this->client->getClientIp();

            if ($ip) {
                $headers['Client-IP'] = $ip;
            }

            $httpClient = new \GuzzleHttp\Client([
                'headers' => $headers,
            ]);

            $this->genericProvider = new \League\OAuth2\Client\Provider\GenericProvider(
                [
                    'clientId' => $this->opts['client_id'],
                    'clientSecret' => $this->opts['client_secret'],
                    'redirectUri' => $this->opts['redirect_uri'],
                    'urlAuthorize' => $this->description->authorize_url,
                    'urlAccessToken' => $this->description->token_url,
                    'urlResourceOwnerDetails' => 'ENOTSUPPORTED',
                    'pkceMethod' => \League\OAuth2\Client\Provider\GenericProvider::PKCE_METHOD_S256,
                    'scopes' => $this->opts['scope'],
                    'scopeSeparator' => ' ',
                ],
                [
                    'httpClient' => $httpClient,
                ]
            );
        }

        if (isset($this->opts['access_token'])) {
            $this->accessToken = new \League\OAuth2\Client\Token\AccessToken($this->opts['access_token']);
        }
    }

    /**
     * Redirect the user to the authorization endpoint to request authorization code
     */
    public function requestAuthorizationCode()
    {
        $authorizationUrl = $this->genericProvider->getAuthorizationUrl();

        $_SESSION['oauth2state'] = $this->genericProvider->getState();
        $_SESSION['oauth2pkceCode'] = $this->genericProvider->getPkceCode();

        header('Accept: text/html');
        header('Location: ' . $authorizationUrl);
        exit;
    }

    /**
     * Request access token based on authorization code
     */
    public function requestAccessToken()
    {
        if (!isset($_GET['state']) || $_GET['state'] != $_SESSION['oauth2state']) {
            throw new \HaveAPI\Client\Exception\AuthenticationFailed('Invalid OAuth2 state');
        }

        $this->genericProvider->setPkceCode($_SESSION['oauth2pkceCode']);

        $this->accessToken = $this->genericProvider->getAccessToken('authorization_code', [
            'code' => $_GET['code'],
        ]);

        if (isset($_SESSION['oauth2state'])) {
            unset($_SESSION['oauth2state']);
        }

        if (isset($_SESSION['oauth2pkceCode'])) {
            unset($_SESSION['oauth2pkceCode']);
        }
    }

    /**
     * Add authorization header to the request
     */
    public function authenticate(\Httpful\Request $request)
    {
        if ($this->accessToken) {
            $request->addHeader('Authorization', 'Bearer ' . $this->accessToken->getToken());
        }
    }

    /*
     * Revoke the access token
     */
    public function logout()
    {
        $this->revokeAccessToken();
    }

    /*
     * Revoke the access token
     * @param array $params additional parameters to be sent to the server
     */
    public function revokeAccessToken($params = [])
    {
        $this->revokeToken(array_merge($params, ['token' => $this->accessToken->getToken()]));
    }

    /*
     * Send request to token revocation endpoint
     * @param array $params
     */
    public function revokeToken($params)
    {
        $request = $this->client->getRequest('post', $this->description->revoke_url);
        $request->sendsForm();

        $encodedParams = [];

        foreach ($params as $k => $v) {
            $encodedParams[] = $k."=".urlencode($v);
        }

        $request->body(implode('&', $encodedParams));
        $request->send();
    }

    /**
     * Return access token serialized in an array
     * @return array
     */
    public function jsonSerialize()
    {
        return $this->accessToken->jsonSerialize();
    }
}
