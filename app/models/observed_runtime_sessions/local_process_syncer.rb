module ObservedRuntimeSessions
  class LocalProcessSyncer
    def self.sync!(scanners: nil)
      new(scanners: scanners).sync!
    end

    def initialize(scanners: nil)
      @scanners = scanners || default_scanners
    end

    def sync!
      scanners.flat_map do |scanner|
        scanner.sessions.filter_map { |session| ingest(session) }
      rescue StandardError => error
        Rails.logger.warn("Local runtime scan failed for #{scanner.class.name}: #{error.class}: #{error.message}")
        []
      end
    end

    private

    attr_reader :scanners

    def default_scanners
      [ RuntimeAdapters::CodexProcessScanner.new ]
    end

    def ingest(session)
      event = session.respond_to?(:to_runtime_event) ? session.to_runtime_event : session
      ObservedRuntimeSessions::Ingestor.new(runtime_name: "codex", event: event).process
    end
  end
end
