require_relative '../spec_helper'
require_relative '../../lib/haveapi/typescript_client/formatter'

RSpec.describe HaveAPI::TypeScriptClient::Generator, '#generate' do
  include TypeScriptFixtures

  it 'formats the complete tree before hashing and preserves an unchanged generation' do
    Dir.mktmpdir('haveapi-formatted-generation-') do |directory|
      # Consumer preferences must not affect the generator's packaged defaults.
      File.write(File.join(directory, '.prettierrc.json'), '{"tabWidth":8,"singleQuote":true}')
      File.write(File.join(directory, '.editorconfig'), "root = true\n[*]\nindent_style = tab\n")
      File.write(File.join(directory, '.prettierignore'), "**/*.ts\n")
      output = File.join(directory, 'src/generated')
      generator = described_class.new(schema: snapshot)
      generator.generate(output:)
      manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
      formatter = HaveAPI::TypeScriptClient::Formatter.new
      expect(manifest.fetch('format')).to eq(1)
      expect(manifest.fetch('formatter')).to eq(formatter.provenance)
      files = manifest.fetch('files').to_h { |path, _digest| [path, File.read(File.join(output, path))] }
      expect(formatter.format(files)).to eq(files)
      expect(files.fetch('api.ts')).to include('import type { ClientOptions } from "./runtime.js";', "\n  return {\n")
      expect(manifest.fetch('files')).to eq(files.transform_values { |content| Digest::SHA256.hexdigest(content) })
      before = Dir.glob('**/*', base: output).select { |path| File.file?(File.join(output, path)) }.to_h do |path|
        full = File.join(output, path)
        [path, [File.binread(full), File.mtime(full)]]
      end
      expect(generator.generate(output:, check: true)).to be(true)
      expect(generator.generate(output:)).to be(true)
      before.each do |path, (content, mtime)|
        expect(File.binread(File.join(output, path))).to eq(content)
        expect(File.mtime(File.join(output, path))).to eq(mtime)
      end
    end
  end
end
