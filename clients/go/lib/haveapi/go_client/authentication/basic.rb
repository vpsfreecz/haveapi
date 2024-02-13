require 'haveapi/go_client/authentication/base'

module HaveAPI::GoClient
  class Authentication::Basic < Authentication::Base
    register :basic

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'authentication/basic.go',
        {
          package: gen.package
        },
        File.join(gen.dst, 'auth_basic.go')
      )
    end
  end
end
