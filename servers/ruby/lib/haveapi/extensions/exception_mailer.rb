require 'net/smtp'
require 'mail'
require 'haveapi/extensions/base'

module HaveAPI::Extensions
  # This extension mails exceptions raised during action execution and description
  # construction to specified e-mail address.
  #
  # The template is based on {Sinatra::ShowExceptions::TEMPLATE}, but the JavaScript
  # functions are removed, since e-mail doesn't support it. HaveAPI-specific content
  # is added. Some helper methods are taken either from Sinatra or Rack.
  class ExceptionMailer < Base
    Frame = Struct.new(:filename, :lineno, :function, :context_line)
    FILTERED_VALUE = '[FILTERED]'.freeze
    SENSITIVE_KEY_PATTERN = /
      authorization|cookie|password|passwd|passphrase|secret|token|
      api[_-]?key|credential|jwt|session|csrf|query_string|form_vars|
      request_uri|original_fullpath|fullpath
    /ix
    SENSITIVE_STRING_PATTERN = /
      (
        (?:authorization|cookie|password|passwd|passphrase|secret|token|
           api[_-]?key|credential|jwt|session|csrf)
        [^=:\s&;<>]{0,64}
        \s*(?:=|:|=>)\s*["']?
      )
      [^&;\s<"'}]+
    /ix

    # @param opts [Hash] options
    # @option opts to [String] recipient address
    # @option opts from [String] sender address
    # @option opts subject [String] '%s' is replaced by the error message
    # @option opts smtp [Hash, falsy] smtp options, sendmail is used if not provided
    def initialize(opts)
      super()
      @opts = opts
    end

    def enabled(server)
      HaveAPI::Action.connect_hook(:exec_exception) do |ret, context, e|
        safe_log(context, e)
        ret
      end

      server.connect_hook(:description_exception) do |ret, context, e|
        safe_log(context, e)
        ret
      end

      server.connect_hook(:request_exception) do |ret, context, e|
        safe_log(context, e)
        ret
      end
    end

    def safe_log(context, exception)
      log(context, exception)
    rescue StandardError => e
      warn "HaveAPI::Extensions::ExceptionMailer failed: #{e.class}: #{e.message}"
    end

    def log(context, exception)
      request_context = context&.request
      req = request_context.respond_to?(:request) ? request_context.request : request_context
      path = request_path(context, req)

      frames = Array(exception.backtrace).map do |line|
        frame = Frame.new

        next unless line =~ /(.*?):(\d+)(:in `(.*)')?/

        frame.filename = ::Regexp.last_match(1)
        frame.lineno = ::Regexp.last_match(2).to_i
        frame.function = ::Regexp.last_match(4)

        begin
          lineno = frame.lineno - 1
          lines = ::File.readlines(frame.filename)
          frame.context_line = lines[lineno].chomp
        rescue StandardError
          # ignore
        end

        frame
      end.compact
      frames = [Frame.new('(unknown)', 0, nil, nil)] if frames.empty?

      args = redact(context&.args)
      path_params = redact(context&.path_params)
      input = redact(context&.input)
      get = request_params(req, :GET)
      post = request_params(req, :POST)
      cookies = request_cookies(req)
      env = redact(request_env(request_context, req))

      user =
        if context&.current_user.respond_to?(:id)
          context.current_user.id
        else
          context&.current_user
        end

      mail(context, exception, TEMPLATE.result(binding))
    end

    def mail(context, exception, body)
      mail = ::Mail.new({
        from: @opts[:from],
        to: @opts[:to],
        subject: format(@opts[:subject], exception.to_s),
        body:,
        content_type: 'text/html; charset=UTF-8'
      })

      if @opts[:smtp]
        mail.delivery_method(:smtp, @opts[:smtp])

      else
        mail.delivery_method(:sendmail)
      end

      mail.deliver!
      mail
    end

    protected

    # From {Sinatra::ShowExceptions}
    def frame_class(frame)
      if frame.filename =~ %r{lib/sinatra.*\.rb}
        'framework'
      elsif (defined?(Gem) && frame.filename.include?(Gem.dir)) ||
            frame.filename =~ %r{/bin/(\w+)$}
        'system'
      else
        'app'
      end
    end

    # From {Rack::ShowExceptions}
    def h(obj)
      case obj
      when String
        Rack::Utils.escape_html(obj)
      else
        Rack::Utils.escape_html(obj.inspect)
      end
    end

    def request_path(context, req)
      if req.respond_to?(:script_name) && req.respond_to?(:path_info)
        return filter_query_string((req.script_name + req.path_info).squeeze('/'))
      end

      filter_query_string(
        if context.respond_to?(:resolved_path)
          context.resolved_path
        elsif context.respond_to?(:path)
          context.path
        else
          '(unknown)'
        end
      )
    end

    def request_env(request_context, req)
      if request_context.respond_to?(:env)
        request_context.env
      elsif req.respond_to?(:env)
        req.env
      else
        {}
      end
    end

    def request_params(req, method)
      return {} unless req.respond_to?(method)

      redact(req.public_send(method) || {})
    rescue StandardError
      {}
    end

    def request_cookies(req)
      return {} unless req.respond_to?(:cookies)

      cookies = req.cookies || {}

      cookies.each_with_object({}) do |(key, _value), ret|
        ret[key] = FILTERED_VALUE
      end
    rescue StandardError
      {}
    end

    def filter_query_string(path)
      return path unless path.respond_to?(:sub)

      path.sub(/\?.*/, "?#{FILTERED_VALUE}")
    end

    def redact(value, key = nil, seen = nil)
      return FILTERED_VALUE if sensitive_key?(key)

      seen ||= {}.compare_by_identity

      case value
      when Hash
        return value if seen.has_key?(value)

        seen[value] = true
        value.each_with_object({}) do |(inner_key, inner_value), ret|
          ret[inner_key] = redact(inner_value, inner_key, seen)
        end
      when Array
        return value if seen.has_key?(value)

        seen[value] = true
        value.map { |inner_value| redact(inner_value, nil, seen) }
      when String
        redact_string(value)
      else
        value
      end
    end

    def sensitive_key?(key)
      key && key.to_s.match?(SENSITIVE_KEY_PATTERN)
    end

    def redact_string(value)
      value.gsub(SENSITIVE_STRING_PATTERN, "\\1#{FILTERED_VALUE}")
    end

    TEMPLATE = ERB.new(<<~END
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title><%=h exception.class %> at <%=h path %></title>
          <style type="text/css">
        *                   {margin: 0; padding: 0; border: 0; outline: 0;}
        div.clear           {clear: both;}
        body                {background: #EEEEEE; margin: 0; padding: 0;
                             font-family: 'Lucida Grande', 'Lucida Sans Unicode',
                             'Garuda';}
        code                {font-family: 'Lucida Console', monospace;
                             font-size: 12px;}
        li                  {height: 18px;}
        ul                  {list-style: none; margin: 0; padding: 0;}
        ol:hover            {cursor: pointer;}
        ol li               {white-space: pre;}
        #explanation        {font-size: 12px; color: #666666;
                             margin: 20px 0 0 100px;}
      /* WRAP */
        #wrap               {width: 1000px; background: #FFFFFF; margin: 0 auto;
                             padding: 30px 5px 20px 5px;
                             border-left: 1px solid #DDDDDD;
                             border-right: 1px solid #DDDDDD;}
      /* HEADER */
        #header             {margin: 0 auto 25px auto;}
        #header #summary    {margin: 12px 0 0 20px;
                             font-family: 'Lucida Grande', 'Lucida Sans Unicode';}
        h1                  {margin: 0; font-size: 36px; color: #981919;}
        h2                  {margin: 0; font-size: 22px; color: #333333;}
        #header ul          {margin: 0; font-size: 12px; color: #666666;}
        #header ul li strong{color: #444444;}
        #header ul li       {display: inline; padding: 0 10px;}
        #header ul li.first {padding-left: 0;}
        #header ul li.last  {border: 0; padding-right: 0;}
      /* BODY */
        #backtrace,
        #get,
        #post,
        #cookies,
        #rack, #context     {width: 980px; margin: 0 auto 10px auto;}
        p#nav               {float: right; font-size: 14px;}
      /* BACKTRACE */
        h3                  {float: left; width: 100px; margin-bottom: 10px;
                             color: #981919; font-size: 14px; font-weight: bold;}
        #nav a              {color: #666666; text-decoration: none; padding: 0 5px;}
        #backtrace li.frame-info {background: #f7f7f7; padding-left: 10px;
                                 font-size: 12px; color: #333333;}
        #backtrace ul       {list-style-position: outside; border: 1px solid #E9E9E9;
                             border-bottom: 0;}
        #backtrace ol       {width: 920px; margin-left: 50px;
                             font: 10px 'Lucida Console', monospace; color: #666666;}
        #backtrace ol li    {border: 0; border-left: 1px solid #E9E9E9;
                             padding: 2px 0;}
        #backtrace ol code  {font-size: 10px; color: #555555; padding-left: 5px;}
        #backtrace-ul li    {border-bottom: 1px solid #E9E9E9; height: auto;
                             padding: 3px 0;}
        #backtrace-ul .code {padding: 6px 0 4px 0;}
      /* REQUEST DATA */
        p.no-data           {padding-top: 2px; font-size: 12px; color: #666666;}
        table.req           {width: 980px; text-align: left; font-size: 12px;
                             color: #666666; padding: 0; border-spacing: 0;
                             border: 1px solid #EEEEEE; border-bottom: 0;
                             border-left: 0;
                             clear:both}
        table.req tr th     {padding: 2px 10px; font-weight: bold;
                             background: #F7F7F7; border-bottom: 1px solid #EEEEEE;
                             border-left: 1px solid #EEEEEE;}
        table.req tr td     {padding: 2px 20px 2px 10px;
                             border-bottom: 1px solid #EEEEEE;
                             border-left: 1px solid #EEEEEE;}
      /* HIDE PRE/POST CODE AT START */
        .pre-context,
        .post-context       {display: none;}
        table td.code       {width:750px}
        table td.code div   {width:750px;overflow:hidden}
          </style>
        </head>
        <body>
          <div id="wrap">
            <div id="header">
              <div id="summary">
                <h1><strong><%=h exception.class %></strong> at <strong><%=h path %>
                  </strong></h1>
                <h2><%=h exception.message %></h2>
                <ul>
                  <li class="first"><strong>file:</strong> <code>
                    <%=h frames.first.filename.split("/").last %></code></li>
                  <li><strong>location:</strong> <code><%=h frames.first.function %>
                    </code></li>
                  <li class="last"><strong>line:
                    </strong> <%=h frames.first.lineno %></li>
                </ul>
              </div>
              <div class="clear"></div>
            </div>
            <div id="context">
              <h3>Context</h3>
              <table class="req">
                <tr>
                  <th>API version</th>
                  <td><%=h context.version %></td>
                </tr>
                <tr>
                  <th>Action</th>
                  <td><%= h(context.action && context.action.to_s) %></td>
                </tr>
                <tr>
                  <th>Arguments</th>
                  <td><%=h args %></td>
                </tr>
                <tr>
                  <th>Path parameters</th>
                  <td><%=h path_params %></td>
                </tr>
                <tr>
                  <th>Input</th>
                  <td><%=h input %></td>
                </tr>
                <tr>
                  <th>User</th>
                  <td><%=h user %></td>
                </tr>
              </table>
              <div class="clear"></div>
            </div>
            <div id="backtrace">
              <h3>BACKTRACE</h3>
              <p id="nav"><strong>JUMP TO:</strong>
                <a href="#get-info">GET</a>
                <a href="#post-info">POST</a>
                <a href="#cookie-info">COOKIES</a>
                <a href="#env-info">ENV</a>
              </p>
              <div class="clear"></div>
              <ul id="backtrace-ul">
              <% frames.each do |frame| %>
                <li class="frame-info <%= frame_class(frame) %>">
                  <code><%=h frame.filename %></code> in
                  <code><strong><%=h frame.function %></strong></code>
                </li>
                <li class="code <%= frame_class(frame) %>">
                  <ol start="<%= frame.lineno %>" class="context">
                    <li class="context-line">
                      <code><%=h frame.context_line %></code>
                    </li>
                  </ol>
                  <div class="clear"></div>
                </li>
              <% end %>
              </ul>
            </div> <!-- /BACKTRACE -->
            <div id="get">
              <h3 id="get-info">GET</h3>
              <% if !get.empty? %>
                <table class="req">
                  <tr>
                    <th>Variable</th>
                    <th>Value</th>
                  </tr>
                  <% get.sort_by { |k, v| k.to_s }.each { |key, val| %>
                  <tr>
                    <td><%=h key %></td>
                    <td class="code"><div><%=h val.inspect %></div></td>
                  </tr>
                  <% } %>
                </table>
              <% else %>
                <p class="no-data">No GET data.</p>
              <% end %>
              <div class="clear"></div>
            </div> <!-- /GET -->
            <div id="post">
              <h3 id="post-info">POST</h3>
              <% if !post.empty? %>
                <table class="req">
                  <tr>
                    <th>Variable</th>
                    <th>Value</th>
                  </tr>
                  <% post.sort_by { |k, v| k.to_s }.each { |key, val| %>
                  <tr>
                    <td><%=h key %></td>
                    <td class="code"><div><%=h val.inspect %></div></td>
                  </tr>
                  <% } %>
                </table>
              <% else %>
                <p class="no-data">No POST data.</p>
              <% end %>
              <div class="clear"></div>
            </div> <!-- /POST -->
            <div id="cookies">
              <h3 id="cookie-info">COOKIES</h3>
              <% unless cookies.empty? %>
                <table class="req">
                  <tr>
                    <th>Variable</th>
                    <th>Value</th>
                  </tr>
                  <% cookies.each { |key, val| %>
                    <tr>
                      <td><%=h key %></td>
                      <td class="code"><div><%=h val.inspect %></div></td>
                    </tr>
                  <% } %>
                </table>
              <% else %>
                <p class="no-data">No cookie data.</p>
              <% end %>
              <div class="clear"></div>
            </div> <!-- /COOKIES -->
            <div id="rack">
              <h3 id="env-info">Rack ENV</h3>
              <table class="req">
                <tr>
                  <th>Variable</th>
                  <th>Value</th>
                </tr>
                <% env.sort_by { |k, v| k.to_s }.each { |key, val| %>
                <tr>
                  <td><%=h key %></td>
                  <td class="code"><div><%=h val %></div></td>
                </tr>
                <% } %>
              </table>
              <div class="clear"></div>
            </div> <!-- /RACK ENV -->
            <p id="explanation">You're seeing this error because you have
        enabled HaveAPI Extension <code>HaveAPI::Extensions::ExceptionMailer</code>.</p>
          </div> <!-- /WRAP -->
        </body>
      </html>
    END
                      )
  end
end
