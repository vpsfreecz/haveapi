require 'cgi'
require 'json'
require 'uri'
require 'haveapi/documentation_search_index'

module HaveAPI
  class DocumentationSearch
    LIMIT = 20
    KIND_ORDER = { resource: 0, action: 1, parameter: 2 }.freeze

    def self.parameter_anchor(resource_path:, action_name:, direction:, parameter_name:, authentication: nil)
      tuple = [authentication&.to_s, resource_path.map(&:to_s), action_name.to_s, direction.to_s, parameter_name.to_s]
      "parameter-#{JSON.generate(tuple).unpack1('H*')}"
    end

    def initialize(index:, query:)
      @index = index
      @query = query
      @needle = query.downcase
      @tokens = @needle.split(/[[:space:]]+/)
    end

    def call
      @matches = []
      records unless @tokens.empty?
      { query: @query, results: @matches.first(LIMIT).map(&:last), more: @matches.length > LIMIT }
    end

    private

    def field(hash, key, default = nil)
      return default unless hash.is_a?(Hash)

      hash.fetch(key) { hash.fetch(key.to_s, default) }
    end

    def records
      field(@index, :resources).each do |resource|
        path = field(resource, :path)
        record = resource_record(resource)
        match(record, field(resource, :search), [path.last, path.join('.')])
      end
      field(@index, :actions).each do |action|
        resource = field(@index, :resources).fetch(field(action, :resource))
        record = action_record(resource, action)
        match(record, action_metadata(resource, action), field(action, :identifiers))
      end
      field(@index, :parameters).each do |parameter|
        action = field(@index, :actions).fetch(field(parameter, :action))
        resource = field(@index, :resources).fetch(field(action, :resource))
        record = action_record(resource, action).merge(kind: :parameter, name: field(parameter, :name),
                                                       label: field(parameter, :label), type: field(parameter, :type),
                                                       direction: field(parameter, :direction).to_sym)
        record[:anchor] = self.class.parameter_anchor(resource_path: record[:resource_path], action_name: record[:action_name],
                                                      direction: record[:direction], parameter_name: record[:name], authentication: record[:authentication])
        metadata = action_metadata(resource, action) + %i[name label type direction humanized_name].map { |name| field(parameter, name) }
        match(record, metadata, [record[:name]])
      end
    end

    def resource_record(resource)
      path = field(resource, :path)
      { kind: :resource, resource_path: path, name: path.last, label: field(resource, :label),
        resource_label: resource_label(resource),
        action_name: nil, direction: nil, type: nil, authentication: field(resource, :authentication),
        anchor: "root-#{path.join('-')}" }
    end

    def resource_label(resource)
      @resource_labels ||= field(@index, :resources).to_h do |entry|
        [[field(entry, :authentication), field(entry, :path)], field(entry, :label)]
      end
      path = field(resource, :path)
      path.each_index.map do |index|
        @resource_labels.fetch([field(resource, :authentication), path.first(index + 1)], path[index])
      end.join(' · ')
    end

    def action_record(resource, action)
      name = field(action, :name)
      resource_record(resource).merge(kind: :action, name:, label: field(action, :label), action_name: name,
                                      anchor: "root-#{field(resource, :path).join('-')}-#{name}")
    end

    def action_metadata(resource, action)
      field(resource, :search) + field(action, :identifiers) + field(action, :search)
    end

    def match(record, metadata, identifiers)
      searchable = metadata.compact.map { |value| value.to_s.downcase }
      text = searchable.join(' ')
      return unless @tokens.all? { |token| text.include?(token) }

      names = identifiers.compact.map { |value| value.to_s.downcase }
      rank = if names.include?(@needle)
               0
             elsif names.any? { |name| name.start_with?(@needle) }
               1
             else
               2
             end
      kind = KIND_ORDER.fetch(record[:kind])
      key = [kind, rank, record[:authentication].to_s, record[:resource_path].join('.'),
             record[:action_name].to_s, record[:name], record[:direction].to_s]
      @matches << [key, record]
      @matches.sort_by!(&:first)
      @matches.pop if @matches.length > LIMIT + 1
    end

    module Helpers
      def documentation_search_query
        documentation_search_parameters[:query]
      end

      def documentation_search_parameters
        return @documentation_search_parameters if defined?(@documentation_search_parameters)

        pairs = request.query_string.split('&').map do |pair|
          key, value = pair.split('=', 2)
          [URI.decode_www_form_component(key), URI.decode_www_form_component(value || '')]
        end
        selected = pairs.select { |key, _| key.match?(/\Aq(?:\[|\z)/) }
        unless selected.length <= 1 && selected.all? { |key, value| key == 'q' && value.valid_encoding? }
          invalid_documentation_search_query
        end
        query = selected.empty? ? '' : selected.first.last.strip
        invalid_documentation_search_query if query.length > 256
        indices = pairs.select { |key, _| key.match?(/\Asearch_index(?:\[|\z)/) }
        headers 'Cache-Control' => 'private, no-store' if indices.any?
        if indices.any? && !(indices.length == 1 && indices.first[0] == 'search_index' &&
                            indices.first[1].match?(/\A(?:current|[0-9a-f]{64})\z/) && selected.empty? &&
                            documentation_selection == { 'page' => 'resources' })
          invalid_documentation_search_query
        end
        @documentation_search_parameters = { query:, index: indices.first&.last }
      rescue ArgumentError
        invalid_documentation_search_query
      end

      def invalid_documentation_search_query
        headers 'Cache-Control' => 'private, no-store'
        halt 400, 'Invalid documentation search query'
      end

      def documentation_search_form_options(id:)
        version = @v || settings.api_server.default_version
        return unless version

        { id:, action: url(settings.api_server.version_prefix(version), false), version:,
          query: @documentation_page == 'resources' ? documentation_search_query : '',
          view_key: @help ? documentation_search_index.key : '',
          index_url: documentation_search_index_url(version:, key: @help ? documentation_search_index.key : 'current') }
      end

      def documentation_search_index
        @documentation_search_index ||= Index.new(description: @help, version: @v,
                                                  base_path: url(settings.api_server.version_prefix(@v), false),
                                                  locale: ::I18n.locale, visibility: current_user ? 'authenticated' : 'anonymous')
      end

      def documentation_search_index_url(version:, key:)
        "#{url(settings.api_server.version_prefix(version), false)}?page=resources&search_index=#{key}"
      end

      def documentation_search_index_request?
        !documentation_search_parameters[:index].nil?
      end

      def render_documentation_search_index
        headers 'Cache-Control' => 'private, no-store'
        index = documentation_search_index
        requested = documentation_search_parameters[:index]
        if requested != 'current' && requested != index.key
          halt 409, 'Search has changed. Reload this page or submit to open current results.'
        end

        content_type 'text/html', charset: 'utf-8'
        add_vary_header('Cookie')
        add_vary_header('Authorization')
        body = erb :'documentation/search_index', layout: false, locals: { search_index: index }
        state_changed = response.headers.any? { |name, value| name.downcase == 'set-cookie' && !Array(value).join.empty? }
        if requested != 'current' && !state_changed
          tag = %("#{index.key}")
          headers 'Cache-Control' => 'private, max-age=86400, immutable', 'ETag' => tag
          conditional = request.env['HTTP_IF_NONE_MATCH'].to_s.split(/\s*,\s*/)
          halt 304, '' if conditional.any? { |value| [tag, "W/#{tag}", '*'].include?(value) }
        end
        body
      end

      def documentation_parameter_anchor(**)
        DocumentationSearch.parameter_anchor(**)
      end

      def documentation_search_results
        @documentation_search_results ||= DocumentationSearch.new(index: documentation_search_index.payload, query: documentation_search_query).call
      end

      def documentation_search_result_url(result)
        if result[:authentication]
          documentation_url(page: 'authentication', anchor: result[:anchor])
        else
          documentation_url(resource: result[:resource_path], anchor: result[:kind] == :resource ? nil : result[:anchor])
        end
      end

      def documentation_search_result_title(result)
        result[:kind] == :resource ? result[:resource_path].join('.') : result[:name]
      end

      def documentation_search_result_context(result)
        context = []
        if result[:kind] == :resource
          context << result[:resource_label] unless result[:resource_label] == documentation_search_result_title(result)
        else
          context << "#{result[:resource_path].join('.')} · #{result[:action_name]}"
        end
        context << "#{result[:direction].to_s.capitalize} · #{result[:type]}" if result[:kind] == :parameter
        context << "Authentication: #{result[:authentication]}" if result[:authentication]
        context << result[:label] if result[:kind] != :resource && result[:label] && result[:label] != result[:name]
        context
      end
    end
  end
end
