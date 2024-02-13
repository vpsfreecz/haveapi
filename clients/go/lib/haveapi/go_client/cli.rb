require 'haveapi/go_client'
require 'optparse'

module HaveAPI::GoClient
  class Cli
    def self.run
      options = {
        package: 'client'
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options] <api url> <destination>"

        opts.on('--version VERSION', 'Use specified API version') do |v|
          options[:version] = v
        end

        opts.on('--module MODULE', 'Name of the generated Go module') do |v|
          options[:module] = v
        end

        opts.on('--package PKG', 'Name of the generated Go package') do |v|
          options[:package] = v
        end
      end

      parser.parse!

      if ARGV.length != 2
        warn 'Invalid arguments'
        puts @global_opt.help
        exit(false)
      end

      g = Generator.new(ARGV[0], ARGV[1], options)
      g.generate
      g.go_fmt
    end
  end
end
