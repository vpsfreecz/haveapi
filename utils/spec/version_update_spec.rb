require 'rspec'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Makefile recipes have no corresponding Ruby class.
RSpec.describe 'JavaScript version update recipes' do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path('../..', __dir__) }
  let(:paths) { %w[clients/js/src/haveapi/client.ts clients/js/dist/haveapi-client.js] }

  ["'", '"'].each do |quote|
    it "updates #{quote}-quoted source and bundle versions without changing other source" do
      recipes = File.readlines(File.join(root, 'Makefile')).select do |line|
        line.start_with?("\t@sed") && paths.any? { |path| line.end_with?(" #{path}\n") }
      end
      expect(recipes.length).to eq(2)

      Dir.mktmpdir('haveapi-version-update-') do |dir|
        File.write(File.join(dir, 'Makefile'), "VERSION = 9.8.7\nall:\n#{recipes.join}")
        paths.each do |path|
          FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
          File.write(File.join(dir, path), "Client.Version = #{quote}0.31.0#{quote};\nkeep();\n")
        end
        stdout, stderr, status = Open3.capture3('make', '--no-print-directory', chdir: dir)
        expect(status.success?).to be(true), [stdout, stderr].join("\n")
        paths.each do |path|
          expect(File.read(File.join(dir, path))).to eq("Client.Version = \"9.8.7\";\nkeep();\n")
        end
      end
    end
  end
end
