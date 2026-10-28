require 'spec_helper'
require 'haveapi/documentation_validators'

describe HaveAPI::DocumentationValidators do
  def render(name, options, type: nil)
    described_class.render({ name => options }, type:)
  end

  it 'keeps every rule in a semantic subtable with scoped row headers' do
    html = described_class.render({ present: { empty: false }, include: { values: [false, 0, ''] } })
    expect(html).to include('<table class="docs-validator-table"><caption>Validation rules</caption>',
                            '<th scope="col">Rule</th><th scope="col">Details</th>',
                            '<tr class="docs-validator"><th scope="row">Present</th><td>',
                            '<tr class="docs-validator"><th scope="row">Include</th><td>')
    expect(html.scan('<table').length).to eq(1)
    expect(html.scan('<tr class="docs-validator">').length).to eq(2)
    expect(html).not_to include('<h5>')
    expect(described_class.render({})).to eq('')
    expect(described_class.render(nil)).to eq('')
  end

  it 'explains required presence and its distinct empty-value modes' do
    strict = render(:present, { empty: false, message: 'Required value' })
    expect(strict).to include('Must be supplied and cannot be null.', 'Must not be empty;', 'non-whitespace', 'Required value')
    expect(render(:present, { empty: true })).to include('Empty values are allowed.')
  end

  it 'renders inclusion choices as typed machine values with separate localized labels' do
    values = { 'active' => 'Aktivní', 0 => 'Zero', false => 'Disabled', nil => 'Unset' }
    html = render(:include, { values:, message: 'Select one' })
    expect(html).to include('Allowed values:', '<code>&quot;active&quot;</code>: Aktivní', '<code>0</code>: Zero',
                            '<code>false</code>: Disabled', '<code>null</code>: Unset', 'Select one')
    expect(html).not_to include('=&gt;', '{&quot;active&quot;')
    expect(html.index('Aktivní')).to be < html.index('Zero')
  end

  it 'lists array alternatives, reserved exclusions and empty sets honestly' do
    expect(render(:include, { values: ['', false, 0] })).to include('<code>&quot;&quot;</code>', '<code>false</code>', '<code>0</code>')
    expect(render(:exclude, { values: ['root'] })).to include('Disallowed values:', '&quot;root&quot;')
    expect(render(:exclude, { values: ['root'] })).not_to include('Allowed values:')
    expect(render(:include, { values: [] })).to include('The set is empty.')
    expect(render(:include, { values: {} })).to include('The set is empty.')
  end

  it 'keeps acceptance and confirmation values distinct without coercion' do
    [nil, false, 0, '0'].each do |value|
      expect(render(:accept, { value: })).to include("Must equal <code>#{CGI.escapeHTML(JSON.generate(value))}</code>")
    end
    expect(render(:confirm, { parameter: :password, equal: true })).to include('Must equal parameter <code>password</code>')
    expect(render(:confirm, { parameter: 'password', equal: false })).to include('Must differ from parameter <code>password</code>')
  end

  it 'explains inclusive bounds, step origin, modulo and parity separately' do
    html = render(:number, { min: 3, max: 10, step: 2, mod: 5, odd: true })
    expect(html).to include('Minimum: <code>3</code> (inclusive)', 'Maximum: <code>10</code> (inclusive)',
                            'Step: <code>2</code>, measured from <code>3</code>',
                            'multiple of <code>5</code>, measured from zero', 'Must be odd.', 'Must be a number after parameter type conversion.')
    expect(render(:number, { step: 2, even: true, odd: false })).to include('measured from <code>0</code>', 'Must be even.', 'Odd-only restriction: disabled.')
  end

  it 'describes character length for text and neutral length for unknown types' do
    expect(render(:length, { min: 0, max: 12 }, type: 'String')).to include('Minimum length: <code>0</code> characters', 'Maximum length: <code>12</code> characters')
    expect(render(:length, { equals: 2 }, type: 'Custom')).to include('Length must equal <code>2</code>.')
    expect(render(:length, { equals: 2 }, type: 'Array')).to include('<code>2</code> items')
    expect(render(:length, { equals: 2 }, type: 'Text')).not_to include('bytes')
  end

  it 'shows regex source, negation and descriptions without inventing flags' do
    html = render(:format, { rx: '^[a-z]+$', match: false, description: 'Reserved spelling', message: 'Invalid spelling' })
    expect(html).to include('Must not match this regular expression:', '<code>^[a-z]+$</code>', 'Reserved spelling', 'Validation error message:', 'Invalid spelling')
  end

  it 'labels application-specific rules without claiming generic enforcement' do
    expect(render(:custom, 'Verified by the application')).to include('Application-specific rule: Verified by the application')
    expect(render(:custom, 'Verified by the application')).not_to include('Must pass', 'automatically')
  end

  it 'preserves unknown fields and unexpected shapes with a labelled lossless fallback' do
    html = render('X-Extension', { 'nested' => { 'zero' => 0, 'false' => false, 'empty' => '', 'null' => nil } })
    expect(html).to include('X-Extension', 'JSON:', '&quot;zero&quot;: 0', '&quot;false&quot;: false', '&quot;empty&quot;: &quot;&quot;', '&quot;null&quot;: null')
    expect(render(:include, { values: 'unexpected', message: 'Kept' })).to include('Supplied validator metadata:', 'unexpected', 'Kept')
    expect(render(:number, { min: 'not numeric', message: 'Kept' })).to include('Supplied validator metadata:', 'not numeric', 'Kept')
    expect(render(:include, { values: [], extra: false })).to include('Additional details', CGI.escapeHTML({ extra: false }.inspect), 'Ruby value:')
    expect(render(:include, { values: [:symbol] })).to include('Ruby value:', ':symbol')
  end

  it 'escapes source labels messages and structured options once without mutation' do
    payload = '<script>&"'
    options = { values: { payload => payload }, message: payload, extra: { 'nested' => payload } }
    before = Marshal.dump(options)
    html = render(:include, options)
    expect(html).not_to include('<script>', '&amp;lt;')
    expect(html).to include('&lt;script&gt;&amp;', 'Validation error message:', 'Additional details')
    expect(render(payload, { 'extra' => payload })).to include('<th scope="row">&lt;script&gt;&amp;&quot;</th>')
    expect(Marshal.dump(options)).to eq(before)
  end
end
