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

    private $revokeUrl;

    public function setup()
    {
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
                'verify' => $this->client->verifySsl(),
            ]);

            $this->genericProvider = new \League\OAuth2\Client\Provider\GenericProvider(
                [
                    'clientId' => $this->opts['client_id'],
                    'clientSecret' => $this->opts['client_secret'],
                    'redirectUri' => $this->opts['redirect_uri'],
                    'urlAuthorize' => $this->oauth2EndpointUrl('authorize_url'),
                    'urlAccessToken' => $this->oauth2EndpointUrl('token_url'),
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
     * @param array $queryParams custom query parameters
     */
    public function requestAuthorizationCode($queryParams = [])
    {
        $authorizationUrl = $this->genericProvider->getAuthorizationUrl();

        $_SESSION['oauth2state'] = $this->genericProvider->getState();
        $_SESSION['oauth2pkceCode'] = $this->genericProvider->getPkceCode();

        foreach ($queryParams as $k => $v) {
            $authorizationUrl .= '&' . urlencode($k) . '=' . urlencode($v);
        }

        header('Accept: text/html');
        header('Location: ' . $authorizationUrl);
        exit;
    }

    /**
     * Request access token based on authorization code
     */
    public function requestAccessToken()
    {
        try {
            if (
                !isset($_GET['state'], $_SESSION['oauth2state'])
                || !is_string($_GET['state'])
                || !is_string($_SESSION['oauth2state'])
                || !hash_equals($_SESSION['oauth2state'], $_GET['state'])
            ) {
                throw new \HaveAPI\Client\Exception\AuthenticationFailed('Invalid OAuth2 state');
            }

            if (!isset($_SESSION['oauth2pkceCode']) || !is_string($_SESSION['oauth2pkceCode'])) {
                throw new \HaveAPI\Client\Exception\AuthenticationFailed('Invalid OAuth2 PKCE verifier');
            }

            $this->genericProvider->setPkceCode($_SESSION['oauth2pkceCode']);

            $this->accessToken = $this->genericProvider->getAccessToken('authorization_code', [
                'code' => $_GET['code'],
            ]);
        } finally {
            $this->clearOAuth2Session();
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
        $request = $this->client->getRequest('post', $this->revokeEndpointUrl());
        $request->sendsForm();

        $encodedParams = [];

        foreach ($params as $k => $v) {
            $encodedParams[] = urlencode((string) $k) . "=" . urlencode((string) $v);
        }

        $request->body(implode('&', $encodedParams));
        $request->send();
    }

    private function revokeEndpointUrl()
    {
        if (!$this->revokeUrl) {
            $this->revokeUrl = $this->oauth2EndpointUrl('revoke_url');
        }

        return $this->revokeUrl;
    }

    private function oauth2EndpointUrl($name)
    {
        if (!isset($this->description->$name)) {
            throw new \HaveAPI\Client\Exception\ProtocolError(
                "Invalid OAuth2 $name: missing URL"
            );
        }

        return $this->client->resolveDescriptionUrl(
            $this->description->$name,
            "OAuth2 $name"
        );
    }

    private function clearOAuth2Session()
    {
        if (isset($_SESSION['oauth2state'])) {
            unset($_SESSION['oauth2state']);
        }

        if (isset($_SESSION['oauth2pkceCode'])) {
            unset($_SESSION['oauth2pkceCode']);
        }
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
