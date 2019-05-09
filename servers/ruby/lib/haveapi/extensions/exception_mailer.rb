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
    # @param opts [Hash] options
    # @option opts to [String] recipient address
    # @option opts from [String] sender address
    # @option opts subject [String] '%s' is replaced by the error message
    # @option opts smtp [Hash, falsy] smtp options, sendmail is used if not provided
    def initialize(opts)
      @opts = opts
    end

    def enabled(server)
      HaveAPI::Action.connect_hook(:exec_exception) do |ret, context, e|
        log(context, e)
        ret
      end

      server.connect_hook(:description_exception) do |ret, context, e|
        log(context, e)
        ret
      end
    end

    def log(context, exception)
      req = context.request.request
      path = (req.script_name + req.path_info).squeeze("/")

      frames = exception.backtrace.map { |line|
        frame = OpenStruct.new

        if line =~ /(.*?):(\d+)(:in `(.*)')?/
          frame.filename = $1
          frame.lineno = $2.to_i
          frame.function = $4

          begin
            lineno = frame.lineno-1
            lines = ::File.readlines(frame.filename)
            frame.context_line = lines[lineno].chomp
          rescue
          end

          frame
        else
          nil
        end
      }.compact

      env = context.request.env

      user =
        if context.current_user.respond_to?(:id)
          context.current_user.id
        else
          context.current_user
        end

      mail(context, exception, TEMPLATE.result(binding))
    end

    def mail(context, exception, body)
      mail = ::Mail.new({
        from: @opts[:from],
        to: @opts[:to],
        subject: @opts[:subject] % [exception.to_s],
        body: body,
        content_type: 'text/html; charset=UTF-8',
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
      if frame.filename =~ /lib\/sinatra.*\.rb/
        "framework"
      elsif (defined?(Gem) && frame.filename.include?(Gem.dir)) ||
            frame.filename =~ /\/bin\/(\w+)$/
        "system"
      else
        "app"
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

    TEMPLATE = ERB.new(<<END
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
            <td><%=h context.args %></td>
          </tr>
          <tr>
            <th>Parameters</th>
            <td><%=h context.params %></td>
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
        <% if req.GET and not req.GET.empty? %>
          <table class="req">
            <tr>
              <th>Variable</th>
              <th>Value</th>
            </tr>
            <% req.GET.sort_by { |k, v| k.to_s }.each { |key, val| %>
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
        <% if req.POST and not req.POST.empty? %>
          <table class="req">
            <tr>
              <th>Variable</th>
              <th>Value</th>
            </tr>
            <% req.POST.sort_by { |k, v| k.to_s }.each { |key, val| %>
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
        <% unless req.cookies.empty? %>
          <table class="req">
            <tr>
              <th>Variable</th>
              <th>Value</th>
            </tr>
            <% req.cookies.each { |key, val| %>
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
