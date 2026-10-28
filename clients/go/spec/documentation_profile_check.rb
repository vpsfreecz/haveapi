# Pure mounted-DSL/profile regression. No generation, compiler or listener.
require 'json'
require 'tempfile'
require 'haveapi'
require 'haveapi/go_client/documentation'
require_relative 'support/documentation_profile_fixture'

class GoDocumentationProfileCheck
  FIXTURE = GoDocumentationProfileFixture

  def self.run!
    new.run!
  end

  def run!
    server = FIXTURE.server
    profile = server.documentation_client_profiles('7').fetch(:go)
    assert(profile.package_version.nil?, 'omitted module version must remain unresolved')
    full = FIXTURE.description(server)
    model = HaveAPI::GoClient::ApiVersion.new(full)
    public_description = FIXTURE.description(server, user: :public)
    privileged_description = FIXTURE.description(server, user: :privileged)
    context = FIXTURE.context(public_description)
    adapter = profile.adapter
    saved_token = adapter.instance_variable_get(:@description).dig(:authentication, :token)
    visible_token = public_description.fetch(:authentication).fetch(:token)
    assert(saved_token.fetch(:query_parameter) == '_auth_token', 'automatic profile must capture the JSON String query name')
    assert(visible_token.fetch(:query_parameter) == :_auth_token, 'live token provider must retain its Symbol query name')
    token_example = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: visible_token)
    assert(token_example[:status] == :code, "unexpected token limitation: #{token_example[:reason]}")
    assert(token_example.fetch(:code).include?('api.SetExistingTokenAuth(os.Getenv("HAVEAPI_TOKEN"))'), 'matching token transport must render environment-token code')
    structural = adapter.instance_variable_get(:@description).dig(:resources, :set_timeout_resource, :resources, :child, :actions, :client)
    assert(!structural.has_key?(:examples), 'the private model must not retain example payloads')
    assert(!structural.dig(:input, :parameters, :private_value).has_key?(:default), 'the private model must not retain parameter defaults')
    resolved = adapter.resolve(resource_path: context.resource_path, action_name: 'perform')
    canonical = model.resources.find { |resource| resource.name == 'set_timeout_resource' }
    assert(resolved.resource.parent.go_member_name == canonical.go_member_name, 'full-DSL sibling allocation must be canonical')
    assert(canonical.go_member_name != 'SetTimeoutResource', 'hidden reserved-name sibling must affect allocation')
    assert(resolved.action.go_member_name == 'ClientAction', 'nested action must keep the generator collision name')

    source = code(adapter, context)
    assert(source.start_with?("// go get example.test/current-sdk/client@latest\n"), 'omitted version must emit valid latest selection')
    assert(source.include?('client "example.test/current-sdk/client"'), 'SDK import alias must stay explicit')
    assert(source.include?("api.#{canonical.go_member_name}.Child.ClientAction.Prepare()"), 'rendered nested members must use the full model')
    assert(source.include?('SetPathParamString("parent_id", "parent/with space")'), 'ordered string path argument was lost')
    assert(source.include?('SetPathParamInt("child_id", 0)'), 'ordered zero path argument was lost')
    assert(source.include?('input := invocation.NewInput().SelectParameters()'), 'input omission selection must stay explicit')
    assert(source.include?('input.SetEnabled(false)') && source.include?('input.SetCount(0)'), 'false/zero inputs were lost')
    assert(source.include?("input.SetName(#{JSON.generate(FIXTURE::HOSTILE)})"), 'hostile source literal was not escaped')
    assert(source.include?('response.Output.Owner.Id') && !source.include?('Owner.Label'), 'nested output must use only supplied attributes')
    assert(source.include?('// metadata.SetIncludes(value)'), 'advertised optional includes guidance must remain')
    assert(!source.match?(/private sample|private result|private default|SetPrivateValue|SetUnused|\.PrivateValue/), 'filtered fields or values leaked')

    privileged = code(adapter, FIXTURE.context(privileged_description))
    assert(privileged.include?('input.SetPrivateValue("private sample")'), 'authorized supplied field was lost')
    assert(code(adapter, FIXTURE.context(public_description)) == source, 'sequential users must not change the shared model')
    hidden = full.fetch(:resources).fetch('set_timeout').fetch(:actions).fetch('secret')
    hidden_context = context.with(resource_path: ['set_timeout'], action_name: 'secret', action: hidden,
                                  sample: { status: true, response: { private_value: 'must not leak' } })
    limited(adapter, hidden_context, 'unavailable')

    root_context = FIXTURE.context(public_description, path: ['set_timeout_resource'], action_name: 'child')
    root_source = code(adapter, root_context)
    assert(root_source.include?("api.#{canonical.go_member_name}.ChildAction.Prepare()"), 'resource/action collision was reconstructed incorrectly')
    assert(root_source.include?('input.SetNameNil(true)'), 'nullable supplied input must use the nil setter')

    pinned = FIXTURE.server(module_version: 'v2.3.4', generator_version: HaveAPI::GoClient::VERSION)
    pinned_adapter = pinned.documentation_client_profiles('7').fetch(:go).adapter
    pinned_source = code(pinned_adapter, FIXTURE.context(FIXTURE.description(pinned, user: :public)))
    assert(pinned_source == source.sub('@latest', '@v2.3.4'), 'explicit version must preserve all other rendering')
    check_legacy(full, source)
    $stdout.write("Go documentation profiles: current mounted DSL, optional/pinned versions, legacy data and authorized rendering passed\n") # rubocop:disable RSpec/Output
  end

  private

  def check_legacy(full, current_source)
    Tempfile.create(['haveapi-go-profile-', '.json']) do |file|
      file.write(JSON.generate(full))
      file.flush
      server = FIXTURE.server(description_path: file.path, module_version: 'v2.3.4',
                              generator_version: HaveAPI::GoClient::VERSION)
      adapter = server.documentation_client_profiles('7').fetch(:go).adapter
      context = FIXTURE.context(FIXTURE.description(server, user: :public))
      assert(code(adapter, context) == current_source.sub('@latest', '@v2.3.4'), 'legacy saved profile must preserve current matching rendering')
    end
  end

  def code(adapter, context)
    result = adapter.render(kind: :example, context:, mode: :sync)
    assert(result[:status] == :code, "unexpected limitation: #{result[:reason]}")
    result.fetch(:code)
  end

  def limited(adapter, context, reason)
    result = adapter.render(kind: :example, context:, mode: :sync)
    assert(result[:status] == :limitation && result[:reason].include?(reason), 'hidden action must remain unavailable')
    assert(!result.to_s.include?('must not leak'), 'limitation disclosed the hidden sample')
  end

  def assert(condition, message)
    raise message unless condition
  end
end

GoDocumentationProfileCheck.run! if $0 == __FILE__
