module HaveAPI::Authentication
  module OAuth2
    # Config passed to the OAuth2 provider
    #
    # Create your own subclass and pass it to {HaveAPI::Authentication::OAuth2.with_config}.
    # The created provider can then be added to authentication chain.
    #
    # In general, it is up to the implementation to provide the authentication flow
    # -- render HTML page in {#render_authorize_page} and then process it in
    # {#handle_post_authorize}. The implementation must also handle generation
    # of all needed tokens, their persistence and validity checking.
    class Config
      def initialize(provider, server, v)
        @provider = provider
        @server = server
        @version = v
      end

      # Render authorization page
      #
      # This method can be called on both GET and POST requests, e.g. if the user
      # provided incorrect credentials or if there are multiple authentication
      # steps.
      #
      # It should return full HTML page that will be sent to the user. The page
      # usually contains a login form.
      #
      # @param oauth2_request [Rack::OAuth2::Server::Authorize::Request]
      # @param sinatra_params [Hash] request params
      # @param client [Client]
      # @param auth_result [AuthResult, nil]
      # @return [String] HTML
      def render_authorize_page(oauth2_request, sinatra_params, client, auth_result: nil)

      end

      # Handle POST requests made from {#render_authorize_page}
      #
      # Process form data and return {AuthResult} or nil. When nil is returned
      # the authorization process is aborted and the user is redirected back
      # to the client.
      #
      # @param sinatra_request [Sinatra::Request]
      # @param sinatra_params [Hash] request params
      # @param oauth2_request [Rack::OAuth2::Server::Authorize::Request]
      # @param client [Client]
      # @return [AuthResult, nil]
      def handle_post_authorize(sinatra_request, sinatra_params, oauth2_request, client)

      end

      # Get oauth2 authorization code
      #
      # Called when the authentication is successful and complete. This method
      # must generate and return authorization_code which is then sent to the
      # client. It is up to the API implementation to persist the code.
      #
      # @param auth_res [AuthResult] value returned by {#handle_post_authorize}
      # @return [String]
      def get_authorization_code(auth_res)

      end

      # Get access token, its expiration date and optionally a refresh token
      #
      # The client has used the authorization_code returned by {#get_authorization_code}
      # and now requests its access token. It is up to the implementation to create
      # and persist the tokens. The authorization code should be invalidated.
      #
      # @param authorization [Authorization]
      # @param sinatra_request [Sinatra::Request]
      # @return [Array] access token, expiration date and optional refresh token
      def get_tokens(authorization, sinatra_request)

      end

      # Refresh access token and optionally generate new refresh token
      #
      # The implementation should invalidate the current tokens and generate
      # and persist new ones.
      #
      # @param authorization [Authorization]
      # @param sinatra_request [Sinatra::Request]
      # @return [Array] access token, expiration date and optional refresh token
      def refresh_tokens(authorization, sinatra_request)

      end

      # Find client by ID
      # @param client_id [String]
      # @return [Client, nil]
      def find_client_by_id(client_id)

      end

      # Find authorization by code
      # @param client [Client]
      # @param code [String]
      # @return [Authorization, nil]
      def find_authorization_by_code(client, code)

      end

      # Find authorization by refresh token
      # @param client [Client]
      # @param refresh_token [String]
      # @return [Authorization, nil]
      def find_authorization_by_refresh_token(client, refresh_token)

      end

      # Find user by the bearer token sent in HTTP header or as a query parameter
      # @param sinatra_request [Sinatra::Request]
      # @param access_token [String]
      # @return [Object, nil] user
      def find_user_by_access_token(request, access_token)

      end

      # Path to the authorization endpoint on this API
      # @return [String]
      def authorize_path
        @provider.authorize_path
      end

      # Parameters needed for the authorization process
      #
      # Use these in {#render_authorization_page}, put them e.g. in hidden form
      # fields.
      #
      # @return [Hash<String, String>]
      def oauth2_params(req)
        ret = {
          client_id: req.client_id,
          response_type: req.response_type,
          redirect_uri: req.redirect_uri,
          scope: req.scope.join(' '),
          state: req.state,
        }

        if req.code_challenge.present? && req.code_challenge_method.present?
          ret.update(
            code_challenge: req.code_challenge,
            code_challenge_method: req.code_challenge_method,
          )
        end

        ret
      end
    end
  end
end
