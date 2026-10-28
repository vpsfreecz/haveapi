require 'json'
require 'uri'

module HaveAPI
  # HTML navigation is derived only from this request's authorized description.
  module DocumentationHelpers
    def documentation_identity_name
      settings.api_server.documentation_name || request.host_with_port
    end

    def documentation_document_title
      page = @documentation_title || if @v
                                       case @documentation_page
                                       when 'authentication' then 'Authentication'
                                       when 'resources' then 'Resources'
                                       when 'resource' then @documentation_resource[:label]
                                       else 'Overview'
                                       end
                                     else
                                       'API versions'
                                     end
      version = @v && !@documentation_title ? "API v#{@v}" : nil
      [page, version, documentation_identity_name].compact.join(' · ')
    end

    def documentation_account_context
      return @documentation_account_context if defined?(@documentation_account_context)

      context = if @v && @help
                  { version: @v, user: current_user, authentication: @help[:authentication] }
                else
                  @documentation_index_account
                end
      @documentation_account_context = context && context.merge(controls: documentation_oauth_controls)
    end

    def documentation_neutral_account_url
      server = settings.api_server
      return unless server.versions.length == 1 && server.default_version

      "#{url(server.version_prefix(server.default_version), false)}?page=authentication"
    end

    def render_version_documentation(version)
      headers 'Cache-Control' => 'private, no-store'
      documentation_selection
      documentation_search_query
      @v = version
      documentation_authenticated?(version)
      @help = settings.api_server.describe_version(Context.new(
                                                     settings.api_server,
                                                     version:, user: current_user, params:
                                                   ))
      return render_documentation_search_index if documentation_search_index_request?

      select_documentation_page
      @documentation_ui = true
      content_type 'text/html'
      erb :doc_layout, layout: :main_layout do
        @content = erb :version_page
        @sidebar = erb :version_sidebar
      end
    end

    def documentation_selection?
      documentation_search_index_request? || documentation_selection.any?
    end

    def documentation_selection
      @documentation_selection ||= begin
        query = request.query_string
        halt 400, 'Invalid documentation selection' if query.match?(/%(?![0-9a-f]{2})/i)
        pairs = URI.decode_www_form(query)
        selected = pairs.select { |key, _| key.match?(/\A(?:page|resource)(?:\[|\z)/) }
        unless selected.all? { |key, value| %w[page resource].include?(key) && value.valid_encoding? } &&
               selected.map(&:first).uniq.length == selected.length && selected.length <= 1
          halt 400, 'Invalid documentation selection'
        end
        selected.to_h
      end
    rescue ArgumentError
      halt 400, 'Invalid documentation selection'
    end

    def select_documentation_page
      selection = documentation_selection
      @documentation_page = selection.fetch('page', 'overview')
      unless %w[overview authentication resources].include?(@documentation_page)
        halt 400, 'Invalid documentation selection'
      end
      if @documentation_page == 'resources' && !documentation_search_query.empty?
        @documentation_title = "Search API v#{@v}: #{documentation_search_query}"
      end
      return unless selection.has_key?('resource')

      key = selection['resource']
      unless key.match?(/\A[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*\z/)
        halt 400, 'Invalid documentation selection'
      end
      @documentation_resource = documentation_resources.find { |entry| entry[:key] == key }
      halt 404, 'Documentation resource not found' unless @documentation_resource
      @documentation_page = 'resource'
    end

    def documentation_resources
      @documentation_resources ||= documentation_resource_entries(@help[:resources])
    end

    def documentation_resource_entries(resources, path = [])
      sort_hash(resources).flat_map do |name, info|
        resource_path = path + [name.to_s]
        [{ key: resource_path.join('.'), path: resource_path, info:,
           id: "root-#{resource_path.join('-')}", label: resource_path.map(&:humanize).join(' / ') }] +
          documentation_resource_entries(info[:resources], resource_path)
      end
    end

    def documentation_url(page: nil, resource: nil, anchor: nil)
      query = if resource
                "?resource=#{CGI.escape(Array(resource).join('.'))}"
              elsif page && page != 'overview'
                "?page=#{CGI.escape(page)}"
              else
                ''
              end
      fragment = anchor ? "##{anchor}" : ''
      "#{url(settings.api_server.version_prefix(@v), false)}#{query}#{fragment}"
    end

    def documentation_client_metadata
      documentation_clients.map do |client|
        { id: client.id, language: client.language, language_label: client.language_label, variant: client.variant,
          details: client.detail_levels.map(&:to_s) }
      end
    end

    def documentation_json(value)
      JSON.generate(value).gsub('<', '\\u003c').gsub('>', '\\u003e').gsub('&', '\\u0026')
    end

    def documentation_legacy_anchors
      anchors = { 'api' => documentation_url, 'resources' => documentation_url(page: 'resources'),
                  'auth' => documentation_url(page: 'authentication') }
      documentation_resources.each do |entry|
        destination = documentation_url(resource: entry[:key])
        anchors[entry[:id]] = destination
        entry[:info][:actions].each do |action, info|
          anchors["#{entry[:id]}-#{action}"] = destination
          anchors["example-#{entry[:key]}-#{action}-"] = destination unless info[:examples].empty?
        end
      end
      @help[:authentication].each do |name, info|
        destination = documentation_url(page: 'authentication')
        anchors["auth-#{name}"] = destination
        anchors["auth-#{name}-examples"] = destination
        documentation_clients.each do |client|
          anchors["auth-#{name}-#{client.id}"] = destination
        end
        next unless info[:resources]

        documentation_resource_entries(info[:resources]).each do |entry|
          anchors[entry[:id]] ||= destination
          entry[:info][:actions].each do |action, action_info|
            anchors["#{entry[:id]}-#{action}"] ||= destination
            anchors["example-#{entry[:key]}-#{action}-"] ||= destination unless action_info[:examples].empty?
          end
        end
      end
      anchors
    end
  end
end
