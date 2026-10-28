module HaveAPI
  module SharedDocumentationHelpers
    def render_documentation_index
      render_neutral_documentation(content: erb(:index), title: 'API versions', page: 'versions')
    end

    def render_shared_documentation(content:, title:, sidebar: nil)
      render_neutral_documentation(content:, title:, sidebar:, page: 'guide')
    end

    def shared_documentation_url(path = '')
      url("#{root}#{path}", false)
    end

    def shared_documentation_reference_url(page: nil)
      version = settings.api_server.default_version
      return if version.nil?

      path = settings.api_server.version_prefix(version)
      path += "?page=#{CGI.escape(page)}" if page
      url(path, false)
    end

    private

    def render_neutral_documentation(content:, title:, page:, sidebar: nil)
      headers 'Cache-Control' => 'private, no-store'
      @documentation_ui = true
      @documentation_page = page
      @documentation_title = title
      @documentation_resource = nil
      @v = nil
      @documentation_toc = sidebar
      content_type 'text/html'
      erb :doc_layout, layout: :main_layout do
        @content = erb :shared_documentation, locals: { content: shared_documentation_tables(content), title: }
        @sidebar = erb :shared_sidebar
      end
    end

    def shared_documentation_tables(content)
      # Trusted repository HTML is rendered before this presentation-only pass.
      content.gsub(%r{<table\b[^>]*>.*?</table>}m) do |table|
        %(<div class="docs-table-scroll" role="region" aria-label="Documentation table" tabindex="0">#{table}</div>)
      end
    end
  end
end
