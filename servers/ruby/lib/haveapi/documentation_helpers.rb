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
                                       when 'authentication' then documentation_t('labels.authentication')
                                       when 'resources' then documentation_t('labels.resources')
                                       when 'resource' then @documentation_resource[:key]
                                       else documentation_t('labels.overview')
                                       end
                                     else
                                       documentation_t('labels.api_versions')
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
      return unless server.versions.length == 1 && server.default_version && documentation_oauth_controls

      "#{url(server.version_prefix(server.default_version), false)}?page=authentication"
    end

    def documentation_authenticated?(version)
      @current_user = nil
      @current_user = documentation_authenticate(version)
      settings.api_server.call_hooks_for(:post_authenticated, args: [@current_user])
      resolve_request_locale(@current_user)
      @current_user
    end

    def documentation_oauth_controls
      nil
    end

    def render_version_documentation(version)
      headers 'Cache-Control' => 'private, no-store'
      documentation_selection
      documentation_search_query
      @v = version
      documentation_authenticated?(version)
      with_documentation_locale do
        render_localized_version_documentation(version)
      end
    end

    def render_localized_version_documentation(version)
      @help = settings.api_server.describe_version(Context.new(
                                                     settings.api_server,
                                                     version:, user: current_user, params:
                                                   ))
      return render_documentation_search_index if documentation_search_index_request?

      select_documentation_page
      documentation_example_selection
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
        halt 400, documentation_t('errors.selection') if query.match?(/%(?![0-9a-f]{2})/i)
        pairs = URI.decode_www_form(query)
        selected = pairs.select { |key, _| key.match?(/\A(?:page|resource)(?:\[|\z)/) }
        unless selected.all? { |key, value| %w[page resource].include?(key) && value.valid_encoding? } &&
               selected.map(&:first).uniq.length == selected.length && selected.length <= 1
          halt 400, documentation_t('errors.selection')
        end
        selected.to_h
      end
    rescue ArgumentError
      halt 400, documentation_t('errors.selection')
    end

    def select_documentation_page
      selection = documentation_selection
      @documentation_page = selection.fetch('page', 'overview')
      unless %w[overview authentication resources].include?(@documentation_page)
        halt 400, documentation_t('errors.selection')
      end
      if @documentation_page == 'resources' && !documentation_search_query.empty?
        @documentation_title = documentation_t('titles.search', version: @v, query: documentation_search_query)
      end
      return unless selection.has_key?('resource')

      key = selection['resource']
      unless key.match?(/\A[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*\z/)
        halt 400, documentation_t('errors.selection')
      end
      @documentation_resource = documentation_resources.find { |entry| entry[:key] == key }
      halt 404, documentation_t('errors.resource_not_found') unless @documentation_resource
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

    def documentation_reference_anchor(section:, resource_path: [], action_name: nil, authentication: nil, example_index: nil)
      tuple = [authentication&.to_s, resource_path.map(&:to_s), action_name&.to_s, section.to_s, example_index]
      "reference-#{JSON.generate(tuple).encode(Encoding::UTF_8).unpack1('H*')}"
    end

    def documentation_resource_target(resource_path:, action_name: nil, authentication: nil)
      if authentication
        documentation_reference_anchor(resource_path:, action_name:, authentication:, section: action_name ? :action : :resource)
      else
        "root-#{resource_path.join('-')}#{"-#{action_name}" if action_name}"
      end
    end

    def documentation_action_sections(info, resource_path:, action_name:, authentication: nil)
      sections = { input: documentation_t('labels.input_parameters'), output: documentation_t('labels.output_parameters') }
      sections[:examples] = documentation_t('labels.examples') unless info[:examples].empty?
      sections.map do |section, label|
        { id: documentation_reference_anchor(resource_path:, action_name:, authentication:, section:), label: }
      end
    end

    def documentation_reference_alias(id)
      @documentation_reference_aliases ||= {}
      return '' if @documentation_reference_aliases[id]

      @documentation_reference_aliases[id] = true
      "<span class=\"docs-legacy-anchor\" id=\"#{escape_html(id)}\"></span>"
    end

    def documentation_permalink(id, label)
      "<a class=\"docs-permalink\" href=\"##{escape_html(id)}\" aria-label=\"#{escape_html(documentation_t('accessibility.link_to', label:))}\"><span aria-hidden=\"true\">#</span></a>"
    end

    def documentation_example_selection
      return @documentation_example_selection if defined?(@documentation_example_selection)

      keys = %w[example_language example_client example_detail]
      pairs = URI.decode_www_form(request.query_string, Encoding::ASCII_8BIT).map do |key, value|
        [key.force_encoding(Encoding::UTF_8), value.force_encoding(Encoding::UTF_8)]
      end
      selected = pairs.select { |key, _| key.match?(/\Aexample_(?:language|client|detail)(?:\[|\z)/) }
      unless selected.all? { |key, value| keys.include?(key) && key.valid_encoding? && value.valid_encoding? } &&
             selected.map(&:first).uniq.length == selected.length
        halt 400, documentation_t('errors.selection')
      end
      requested = selected.to_h
      clients = documentation_clients
      client = clients.find { |entry| entry.id == requested['example_client'] }
      language = if requested.has_key?('example_language')
                   requested['example_language']
                 else
                   client&.language
                 end
      group = clients.select { |entry| entry.language == language }
      if group.empty?
        language = clients.first&.language
        group = clients.select { |entry| entry.language == language }
      end
      client = group.find { |entry| entry.id == requested['example_client'] } || group.first
      @documentation_example_selection = {
        client:, language:, detail: requested['example_detail'] == 'thorough' ? 'thorough' : 'simple',
        explicit: selected.any?
      }
    rescue ArgumentError
      halt 400, documentation_t('errors.selection')
    end

    def documentation_example_detail(levels)
      requested = documentation_example_selection[:detail]
      levels.include?(requested) ? requested : 'simple'
    end

    def documentation_example_form_parameters
      parameters = documentation_selection.to_a
      parameters << ['q', documentation_search_query] unless documentation_search_query.empty?
      parameters << ['doc_lang', documentation_locale_override] if documentation_locale_override
      parameters
    end

    def documentation_client_metadata
      documentation_clients.map do |client|
        { id: client.id, language: client.language, language_label: client.language_label, variant: documentation_client_variant(client),
          details: (@documentation_page_details || {}).fetch(client.id, [:simple]).map(&:to_s) }
      end
    end

    def documentation_client_label(client)
      case client.id
      when 'go' then documentation_t('generated.labels.go', default: client.label)
      when 'rust-async' then documentation_t('generated.labels.rust_async', default: client.label)
      when 'rust-blocking' then documentation_t('generated.labels.rust_blocking', default: client.label)
      when 'typescript-generated' then documentation_t('generated.labels.typescript', default: client.label)
      else client.label
      end
    end

    def documentation_client_variant(client)
      case client.id
      when 'rust-async' then documentation_t('generated.variants.async', default: client.variant)
      when 'rust-blocking' then documentation_t('generated.variants.blocking', default: client.variant)
      when 'typescript-generated' then documentation_t('generated.variants.api_client', default: client.variant)
      else client.variant
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

    private

    def documentation_authenticate(_version)
      nil
    end
  end
end
