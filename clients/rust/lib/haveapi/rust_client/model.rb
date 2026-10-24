module HaveAPI::RustClient
  # Pure rules shared by generated SDKs and their documentation examples.
  module Model
    def self.validate_package(crate_name:, crate_version: nil, required_version: false)
      unless crate_name.is_a?(String) && crate_name.match?(/\A[a-z][a-z0-9_-]*\z/) &&
             ((crate_version.nil? && !required_version) ||
              (crate_version.is_a?(String) && crate_version.match?(/\A\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\z/)))
        raise Error, 'invalid crate name/version'
      end

      nil
    end

    def rust_type(parameter, output: false)
      case parameter[:desc].fetch('type')
      when 'String', 'Text', 'Datetime' then 'String'
      when 'Integer', 'Resource' then output && parameter[:desc]['type'] == 'Resource' ? 'runtime::Association' : 'i64'
      when 'Float' then 'f64'
      when 'Boolean' then 'bool'
      when 'Custom' then 'serde_json::Value'
      end
    end

    def meta_parameters(action)
      values = [action[:global_output]]
      values << action[:object_output] if action[:output] && !action[:output][:layout].end_with?('_list')
      fields = values.compact.flat_map { |io| io[:parameters] }
      fields.group_by { |field| field[:name] }.map do |name, matches|
        raise Error, "inconsistent metadata field #{name}" if matches.map { |field| field[:desc] }.uniq.length > 1

        matches.first
      end.sort_by { |field| field[:name] }
    end
  end
end
