require 'rspec'
require 'stringio'
require_relative '../registry_query'

RSpec.describe HaveAPI::Release::RegistryQuery do
  let(:state) { { now: [0.0], sleeps: [], calls: [], lines: [], responses: [] } }
  let(:transport) do
    lambda do |uri, remaining|
      calls << [uri, remaining]
      result = responses.shift
      raise 'Unexpected metadata read' if result.nil?
      raise result if result.is_a?(Exception)

      result.respond_to?(:call) ? result.call : result
    end
  end
  let(:reader) do
    described_class.new(clock: -> { now[0] }, wall_clock: -> { wall_time + now[0] },
                        sleeper: lambda { |seconds|
                          sleeps << seconds
                          now[0] += seconds
                        },
                        transport:, logger: ->(line) { lines << line })
  end
  let(:url) { 'https://rubygems.org/api/v2/rubygems/haveapi-rust-client/versions/0.30.0.json' }
  let(:wall_time) { Time.utc(2026, 10, 22, 21) }

  %i[now sleeps calls lines responses].each do |name|
    define_method(name) { state.fetch(name) }
  end

  def response(status, data = nil, headers = {})
    [status, JSON.generate(data), headers]
  end

  def observe(**options, &validator)
    reader.observe(url, phase: 'post-upload', package: 'haveapi-rust-client', version: '0.30.0',
                        complete: ->(value) { value == { 'confirmed' => true } }, **options,
                   &validator || ->(data) { data })
  end

  before { allow(Net::HTTP).to receive(:new).and_raise('Real registry access is forbidden in unit tests') }

  it 'uses one canonical read when metadata is complete' do
    responses << response(200, { confirmed: true })
    expect(observe).to eq('confirmed' => true)
    expect(calls.map { |uri, _remaining| uri.to_s }).to eq([url])
    expect(sleeps).to be_empty
  end

  it 'checks a cache-distinct exact endpoint after a canonical negative' do
    responses.push(response(404), response(200, { confirmed: true }))
    expect(observe).to eq('confirmed' => true)
    expect(calls.last.first.to_s).to match(/\A#{Regexp.escape(url)}\?haveapi_confirmation=[0-9a-f]{32}\z/)
    expect(sleeps).to be_empty
  end

  it 'returns preflight absence after exactly two validated missing reads' do
    responses.push(response(404), response(404))
    expect(observe).to be_nil
    expect(calls.size).to eq(2)
    expect(sleeps).to be_empty
  end

  it 'repeats only confirmation GETs with bounded backoff until success' do
    10.times { responses << response(404) }
    responses << response(200, { confirmed: true })
    expect(observe(wait: true)).to eq('confirmed' => true)
    expect(sleeps).to eq([2, 4, 8, 15, 30])
    fresh = calls.map(&:first).filter_map(&:query)
    expect(fresh.uniq).to eq(fresh)
  end

  it 'stops at the absolute deadline without a final sleep or request' do
    100.times { responses << response(404) }
    expect { observe(wait: true, deadline: 10, uploaded: true, later: %w[npm PHP]) }
      .to raise_error(HaveAPI::Release::Error, /upload succeeded.*pending.*npm, PHP/)
    expect(sleeps).to eq([2, 4])
    expect(calls.size).to eq(6)
    expect(calls.map(&:last)).to eq([10, 10, 8, 8, 4, 4])
  end

  it 'does not accept a result returned after its request deadline' do
    responses << lambda {
      now[0] = 11
      response(200, { confirmed: true })
    }
    expect { observe(wait: true, deadline: 10) }.to raise_error(HaveAPI::Release::Error, /timed out/)
    expect(calls.size).to eq(1)
    expect(sleeps).to be_empty
  end

  it 'makes no request once a shared deadline is already exhausted' do
    expect { observe(wait: true, deadline: 0) }.to raise_error(HaveAPI::Release::Error, /timed out/)
    expect(calls).to be_empty
  end

  [408, 429, 500, 502, 503, 504].each do |status|
    it "retries temporary HTTP #{status} within the preflight deadline" do
      responses.push(response(status), response(200, { confirmed: true }))
      expect(observe).to eq('confirmed' => true)
      expect(sleeps).to eq([2])
    end
  end

  [Net::ReadTimeout.new, Net::OpenTimeout.new, Errno::ECONNRESET.new,
   Errno::ECONNREFUSED.new, SocketError.new('Temporary failure in name resolution')].each do |error|
    it "retries temporary #{error.class} without logging exception contents" do
      responses.push(error, response(200, { confirmed: true }))
      expect(observe).to eq('confirmed' => true)
      expect(sleeps).to eq([2])
      expect(lines.join).not_to include(error.message)
    end
  end

  it 'gives transient preflight reads at most sixty seconds' do
    20.times { responses << response(503) }
    expect { observe }.to raise_error(HaveAPI::Release::Error, /timed out/)
    expect(sleeps).to eq([2, 4, 8, 15, 30])
    expect(now[0]).to eq(59)
    expect(calls.last.last).to eq(1)
  end

  it 'honors Retry-After seconds instead of retrying early' do
    responses.push(response(429, nil, { 'Retry-After' => '12' }), response(200, { confirmed: true }))
    expect(observe).to eq('confirmed' => true)
    expect(sleeps).to eq([12])
  end

  it 'honors an HTTP date Retry-After' do
    responses.push(response(503, nil, { 'retry-after' => (wall_time + 7).httpdate }), response(200, { confirmed: true }))
    expect(observe).to eq('confirmed' => true)
    expect(sleeps).to eq([7])
  end

  it 'does not retry earlier when Retry-After cannot fit the deadline' do
    responses << response(429, nil, { 'Retry-After' => '61' })
    expect { observe }.to raise_error(HaveAPI::Release::Error, /timed out/)
    expect(sleeps).to be_empty
    expect(calls.size).to eq(1)
  end

  it 'uses bounded backoff for an invalid Retry-After' do
    responses.push(response(503, nil, { 'Retry-After' => 'later' }), response(200, { confirmed: true }))
    expect(observe).to eq('confirmed' => true)
    expect(sleeps).to eq([2])
  end

  [429, 503].each do |status|
    ['0', 'Thu, 22 Oct 2026 20:00:00 GMT', 'invalid'].each do |value|
      it "retains positive finite backoff for HTTP #{status} Retry-After #{value.inspect}" do
        20.times { responses << response(status, nil, { 'Retry-After' => value }) }
        expect { observe(wait: true, deadline: 10) }.to raise_error(HaveAPI::Release::Error, /timed out/)
        expect(sleeps).to eq([2, 4])
        expect(calls.size).to eq(3)
      end
    end

    it "honors HTTP #{status} server delays above thirty seconds when they fit" do
      responses.push(response(status, nil, { 'Retry-After' => '45' }), response(200, { confirmed: true }))
      expect(observe).to eq('confirmed' => true)
      expect(sleeps).to eq([45])
    end

    it "refuses to retry HTTP #{status} before a server delay beyond the deadline" do
      responses << response(status, nil, { 'Retry-After' => (wall_time + 61).httpdate })
      expect { observe }.to raise_error(HaveAPI::Release::Error, /timed out/)
      expect(calls.size).to eq(1)
      expect(sleeps).to be_empty
    end
  end

  [301, 302, 307, 400, 401, 403, 422, 501].each do |status|
    it "fails immediately on permanent HTTP #{status}" do
      responses << response(status)
      expect { observe(wait: true) }.to raise_error(HaveAPI::Release::Error, /HTTP #{status}/)
      expect(calls.size).to eq(1)
      expect(sleeps).to be_empty
    end
  end

  [OpenSSL::SSL::SSLError.new('secret'), SocketError.new('Name or service not known')].each do |error|
    it "fails immediately on terminal #{error.class}" do
      responses << error
      expect { observe(wait: true) }.to raise_error(HaveAPI::Release::Error)
      expect(calls.size).to eq(1)
      expect(sleeps).to be_empty
    end
  end

  ['not json', 'null', '[]'].each do |body|
    it "rejects malformed successful metadata #{body.inspect} without an alternate read" do
      responses << [200, body, {}]
      expect { observe(wait: true) }.to raise_error(HaveAPI::Release::Error, /malformed/)
      expect(calls.size).to eq(1)
    end
  end

  it 'does not mask validation conflicts with a cache-distinct read' do
    responses << response(200, { confirmed: false })
    expect { observe(wait: true) { raise HaveAPI::Release::Error, 'checksum conflict' } }
      .to raise_error(HaveAPI::Release::Error, /checksum conflict/)
    expect(calls.size).to eq(1)
    expect(sleeps).to be_empty
  end

  ['http://rubygems.org/api/v2/rubygems/haveapi/versions/0.30.0.json',
   'https://secret@rubygems.org/api/v2/rubygems/haveapi/versions/0.30.0.json',
   'https://rubygems.org:444/api/v2/rubygems/haveapi/versions/0.30.0.json',
   'https://rubygems.org/api/v1/gems/haveapi.json',
   'https://rubygems.org/api/v2/rubygems/haveapi/versions/0.30.0.json?token=secret',
   'https://rubygems.org/api/v2/rubygems/haveapi/versions/0.30.0.json#secret',
   'https://evil.test/haveapi-client/0.30.0'].each do |unsafe|
    it "rejects unsupported metadata URL #{unsafe.split('?').first}" do
      expect { reader.read(unsafe, deadline: 10) }.to raise_error(HaveAPI::Release::Error, /unsupported/)
      expect(calls).to be_empty
    end
  end

  it 'logs only bounded allowlisted headers, never metadata, credentials or signed locations' do
    responses << response(200, { confirmed: true, token: 'body-secret' },
                          { 'Age' => '123', 'Date' => 'https://example.test/?signed=secret', 'X-Cache' => "HIT\n#{'x' * 300}", 'Authorization' => 'header-secret',
                            'Set-Cookie' => 'cookie-secret', 'Location' => 'https://example.test/?signed=secret' })
    observe { |data| data.slice('confirmed') }
    expect(lines.join).to include('Age="123"', 'X-Cache="HIT?')
    expect(lines.join).not_to include('body-secret', 'header-secret', 'cookie-secret', 'https://', "\n", 'x' * 200)
  end

  it 'preserves the default proxy mode and uses verified HTTPS GETs without upload credentials or cookies' do
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '200', body: '{"ok":true}', to_hash: {})
    allow(Net::HTTP).to receive(:new).with('rubygems.org', 443).and_return(http)
    %i[use_ssl= verify_mode= open_timeout= read_timeout= write_timeout=].each { |method| allow(http).to receive(method) }
    allow(http).to receive(:start).and_yield
    allow(Timeout).to receive(:timeout).and_call_original
    allow(http).to receive(:request) do |request|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request['Cache-Control']).to eq('no-cache')
      expect(request['Authorization']).to be_nil
      expect(request['Cookie']).to be_nil
      response
    end
    actual = described_class.new(clock: -> { 0 }).read(url, deadline: 0.5)
    expect(actual.data).to eq('ok' => true)
    expect(Timeout).to have_received(:timeout).with(0.5)
    expect(Net::HTTP).to have_received(:new).with('rubygems.org', 443)
    expect(http).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    %i[open_timeout= read_timeout= write_timeout=].each { |method| expect(http).to have_received(method).with(0.5) }
  end
end
