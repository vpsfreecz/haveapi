# Isolated positive controls. No defect switch enters the benchmark CLI/runtime.
require_relative '../../../benchmarks/endpoints'

control = ARGV.fetch(0)
spec = if %w[query sqlite-clean].include?(control)
         { id: 'sqlite.page', dimensions: { rows: 128, page_size: 32 } }
       else
         { id: 'api.public_get', dimensions: {} }
       end
HaveAPI::Performance::Worker.define_singleton_method(:inventory) { |_profile| [spec] }
# These test-only fault controls use the actual resolved server bundle from
# ordinary RSpec CI. The production worker's root/component input contract is
# unchanged and is tested separately; it has no optional lock fallback.
HaveAPI::Performance::Worker.define_singleton_method(:inputs) do |source, _profile|
  { manifests: { 'servers/ruby/Gemfile' => Digest::SHA256.file(File.join(source, 'servers/ruby/Gemfile')).hexdigest },
    locks: { 'servers/ruby/Gemfile.lock' => Digest::SHA256.file(File.join(HaveAPI::Performance::ROOT, 'servers/ruby/Gemfile.lock')).hexdigest } }
end
HaveAPI::Performance::Worker.singleton_class.prepend(Module.new do
  define_method(:build) do |selected|
    super(selected).tap do |scenario|
      if control == 'query'
        scenario.singleton_class.prepend(Module.new do
          def execute_record
            super
            @base.connection.select_value('SELECT 1')
          end
        end)
      elsif %w[allocation wrong-output].include?(control)
        scenario.singleton_class.prepend(Module.new do
          define_method(:call) do
            Array.new(4000) { Object.new } if control == 'allocation'
            response = super()
            if control == 'wrong-output'
              Rack::MockResponse.new(200, response.headers, response.body.sub('item-1', 'wrong-item'))
            else
              response
            end
          end
        end)
      end
    end
  end
end)
exit HaveAPI::Performance::CLI.new(['worker']).execute
