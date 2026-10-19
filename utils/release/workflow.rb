require_relative 'artifacts'

module HaveAPI
  module Release
    module Workflow
      def self.api(path)
        JSON.parse(Release.capture('gh', 'api', '--paginate', '--slurp', path))
      end

      def self.artifact_id
        run = ENV.fetch('GITHUB_RUN_ID')
        repository = ENV.fetch('GITHUB_REPOSITORY')
        artifacts = api("repos/#{repository}/actions/runs/#{run}/artifacts").flat_map { |page| page.fetch('artifacts') }
        matches = artifacts.select { |artifact| artifact.fetch('name') == "release-#{run}" }
        raise Error, 'Ambiguous retained artifact set' if matches.length > 1

        unless matches.empty?
          artifact = matches.first
          raise Error, 'Original artifacts have expired; do not rebuild a partially published version' if artifact.fetch('expired')

          return artifact.fetch('id').to_s
        end

        # An early failed build can retry. A deleted successful upload cannot.
        (1...Integer(ENV.fetch('GITHUB_RUN_ATTEMPT'))).each do |attempt|
          jobs = api("repos/#{repository}/actions/runs/#{run}/attempts/#{attempt}/jobs").flat_map { |page| page.fetch('jobs') }
          if jobs.any? { |job| job.fetch('steps').any? { |step| step.fetch('name') == 'Retain release artifacts' && step['conclusion'] == 'success' } }
            raise Error, 'Original artifacts are missing; recover the saved files rather than rebuilding'
          end
        end
        ''
      end

      def self.check_activation
        raise Error, 'Set HAVEAPI_RELEASE_ENABLED=true only after completing release setup' unless ENV['HAVEAPI_RELEASE_ENABLED'] == 'true'

        environment = api("repos/#{REPOSITORY}/environments/release").first
        protected = environment.fetch('protection_rules').any? do |rule|
          rule.fetch('type') == 'required_reviewers' && !rule.fetch('reviewers').empty?
        end
        raise Error, 'The release environment must have required reviewers' unless protected
      end
    end
  end
end
