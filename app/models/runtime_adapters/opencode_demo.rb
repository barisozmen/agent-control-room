module RuntimeAdapters
  class OpencodeDemo
    def self.start!(project_path:, opencode_cli: default_opencode_cli)
      RuntimeAdapters::ScriptedDemo.start!(runtime_name: "opencode", project_path: project_path, cli: opencode_cli)
    end

    def self.default_opencode_cli
      Rails.env.test? ? RuntimeAdapters::OpencodeCli::Noop.new : RuntimeAdapters::OpencodeCli.new
    end

    private_class_method :default_opencode_cli
  end
end
