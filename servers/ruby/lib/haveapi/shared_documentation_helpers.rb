module HaveAPI
  module SharedDocumentationHelpers
    def render_documentation_index
      render_neutral_documentation(content: erb(:index), title: documentation_t('labels.api_versions'), page: 'versions')
    end

    def render_shared_documentation(content:, title:, sidebar: nil)
      render_neutral_documentation(content:, title:, sidebar:, page: 'guide')
    end

    def render_shared_readme
      render_shared_article('readme')
    end

    def documentation_article_path(article, extension: 'md')
      halt 404 unless article.match?(/\A[a-z0-9-]+\z/) && %w[md html].include?(extension)

      directory = File.expand_path('../../doc', __dir__)
      locale = documentation_locale
      path = File.join(directory, locale, "#{article}.#{extension}")
      unless File.file?(path)
        locale = 'en'
        path = File.join(directory, locale, "#{article}.#{extension}")
      end
      halt 404 unless File.file?(path)

      @documentation_article_locale = locale
      path
    end

    def render_shared_article(article)
      @documentation_article_id = article
      content = if article == 'json-schema'
                  File.read(documentation_article_path(article, extension: 'html'))
                else
                  doc(article)
                end
      title = documentation_t("articles.#{article.tr('-', '_')}", default: article.humanize)
      sidebar = begin
        erb :"doc_sidebars/#{article}"
      rescue Errno::ENOENT
        nil
      end
      render_shared_documentation(content:, title:, sidebar:)
    rescue Errno::ENOENT
      halt 404
    end

    def shared_documentation_links(content)
      content.gsub(/(href|src)="([^"#]*)(#[^"]*)?"/) do |attribute|
        kind = Regexp.last_match(1)
        path = Regexp.last_match(2)
        fragment = Regexp.last_match(3).to_s
        if path.match?(%r{\A(?:(?:\.\./)*(?:en/|cs/)?|/doc/(?:en/|cs/)?)[a-z0-9-]+\.md\z})
          article = File.basename(path, '.md')
          %(#{kind}="#{escape_html(shared_documentation_url("doc/#{article}"))}#{fragment}")
        elsif path.match?(%r{\A(?:\.\./)+[a-z0-9-]+\.png\z})
          %(#{kind}="#{escape_html(shared_documentation_url("doc/#{File.basename(path)}"))}#{fragment}")
        else
          attribute
        end
      end
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
        %(<div class="docs-table-scroll" role="region" aria-label="#{escape_html(documentation_t('accessibility.documentation_table'))}" tabindex="0">#{table}</div>)
      end
    end
  end
end
