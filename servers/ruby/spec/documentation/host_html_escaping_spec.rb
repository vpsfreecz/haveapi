# frozen_string_literal: true

require 'spec_helper'

module HostHtmlEscapingSpec
end

describe HostHtmlEscapingSpec do
  api do
    define_resource(:Widget) do
      version 1
      auth false

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }
      end
    end
  end

  default_version 1

  it 'escapes request Host values in HTML docs and generated code examples' do
    payload = 'evil.test"><script>window.__haveapi_host_xss=1</script>'

    header 'Host', payload
    get '/v1/'

    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/html')
    expect(last_response.body).not_to include('class="login')
    expect(last_response.body).not_to include(
      '<script>window.__haveapi_host_xss=1</script>'
    )
    expect(last_response.body).to include(
      'evil.test&quot;&gt;&lt;script&gt;window.__haveapi_host_xss=1&lt;/script&gt;'
    )
    expect(last_response.body).to include(
      'http://evil.test&quot;&gt;&lt;script&gt;window.__haveapi_host_xss=1&lt;/script&gt;'
    )
  end
end
