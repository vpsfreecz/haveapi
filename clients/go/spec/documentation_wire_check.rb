# Pure verifier regression: no generator, compiler or listener is started.
require 'stringio'
require 'uri'
require_relative 'documentation_acceptance'

class GoDocumentationWireCheck
  OBJECT_BODY = JSON.parse('{"widget":{"count":0,"enabled":false,"name":null},"_meta":{}}').freeze
  OBJECT_CASES = %i[object basic_call token_call oauth2_call].freeze

  def self.run!
    OBJECT_CASES.each do |name|
      verify(name, OBJECT_BODY)
      reject_change(name) { |body| body['_meta'] = { 'includes' => 'unrequested' } }
      reject_change(name) { |body| body['_meta'] = nil }
      reject_change(name) { |body| body.delete('_meta') }
      reject_change(name) { |body| body['extra'] = 'unrequested' }
      reject_change(name) { |body| body['widget']['unused'] = '' }
      reject_change(name) { |body| body['widget']['enabled'] = true }
      reject_change(name) { |body| body['widget']['count'] = 1 }
      reject_change(name) { |body| body['widget']['name'] = '' }
      %w[name enabled count].each do |field|
        reject_change(name) { |body| body['widget'].delete(field) }
      end
    end

    hostile = { 'widget' => { 'name' => "quote\"\\\n雪</script>" }, '_meta' => {} }
    verify(:hostile, hostile)
    reject_change(:hostile, hostile) { |body| body['_meta']['includes'] = 'unrequested' }
    reject_change(:hostile, hostile) { |body| body['widget']['unused'] = '' }

    %i[empty omitted].each do |name|
      body = { 'widget' => {} }
      verify(name, body)
      reject_change(name, body) { |changed| changed['_meta'] = {} }
      reject_change(name, body) { |changed| changed['widget']['unused'] = '' }
      reject_change(name, body) { |changed| changed.delete('widget') }
    end
    check_query
    $stdout.write("Go documentation wire verifier: 7 accepted bodies and 52 rejected mutations\n") # rubocop:disable RSpec/Output
    $stdout.write("Go documentation query verifier: 1 accepted query and 8 rejected mutations\n") # rubocop:disable RSpec/Output
  end

  def self.check_query
    verify_query('widget%5Bcount%5D=0&widget%5Benabled%5D=0&widget%5Bname%5D=')
    original = { 'widget[name]' => '', 'widget[enabled]' => '0', 'widget[count]' => '0' }
    [
      original.merge('widget[enabled]' => 'false'),
      original.merge('widget[enabled]' => '1'),
      original.merge('widget[count]' => '1'),
      original.merge('widget[name]' => 'null'),
      *original.keys.map { |key| original.reject { |name, _value| name == key } },
      original.merge('widget[unused]' => '')
    ].each { |query| reject_query(URI.encode_www_form(query)) }
  end

  def self.verify_query(raw_query)
    request = WEBrick::HTTPRequest.new(WEBrick::Config::HTTP)
    request.parse(StringIO.new("GET /mounted/v7/query?#{raw_query} HTTP/1.1\r\nHost: fixture.invalid\r\n\r\n"))
    response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
    runner = GoDocumentationAcceptance.allocate
    runner.instance_variable_set(:@requests, Queue.new)
    runner.send(:serve, request, response)
    runner.send(:verify, :query, GoDocumentationAcceptance.expected_cases.fetch(:query), '')
  end

  def self.reject_query(raw_query)
    verify_query(raw_query)
    raise 'query: verifier accepted an unexpected query'
  rescue RuntimeError => e
    raise unless e.message.start_with?('query: query values were not preserved: expected ') &&
                 e.message.include?('got ') && e.message.include?("raw query #{raw_query.inspect}")
  end

  def self.verify(name, body)
    expected = GoDocumentationAcceptance.expected_cases.fetch(name)
    runner = GoDocumentationAcceptance.allocate
    requests = Queue.new
    path = %i[empty omitted].include?(name) ? "/mounted/v7/#{name}" : '/mounted/v7/clients/42/children/a/b'
    requests << { path:, body: JSON.generate(body), auth: expected.fetch(:auth, {}) }
    runner.instance_variable_set(:@requests, requests)
    runner.send(:verify, name, expected, expected.fetch(:output, ''))
  end

  def self.reject_change(name, original = OBJECT_BODY)
    body = Marshal.load(Marshal.dump(original))
    yield(body)
    verify(name, body)
    raise "#{name}: verifier accepted an unexpected body"
  rescue RuntimeError => e
    raise unless e.message.start_with?("#{name}: supplied input or omission was not preserved:")
  end
end

GoDocumentationWireCheck.run! if $0 == __FILE__
