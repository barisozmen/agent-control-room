require "json"
require "set"

module RuntimeAdapters
  class PiSessionLogScanner
    SessionContext = Data.define(:session_id, :title, :project_path, :started_at, :updated_at, :path)

    def initialize(pi_home: ENV.fetch("PI_CODING_AGENT_DIR", File.join(Dir.home, ".pi", "agent")), session_dir: ENV["PI_CODING_AGENT_SESSION_DIR"], limit: 12, active_project_paths: nil, process_scanner: RuntimeAdapters::PiProcessScanner.new)
      @pi_home = Pathname.new(pi_home)
      @session_dir = session_dir.present? ? Pathname.new(session_dir) : @pi_home.join("sessions")
      @limit = limit
      @active_project_paths = active_project_paths
      @process_scanner = process_scanner
    end

    def sessions
      contexts = recent_session_paths.filter_map { |path| context_for(path) }
      running_session_ids = running_session_ids_for(contexts)

      contexts.flat_map do |context|
        events_for(context, running: running_session_ids.include?(context.session_id))
      end
    end

    private

    attr_reader :session_dir, :limit, :active_project_paths, :process_scanner

    def recent_session_paths
      Dir.glob(session_dir.join("**", "*.jsonl"))
        .sort_by { |path| -File.mtime(path).to_f }
        .first(limit)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    def context_for(path)
      header = first_json_record(path)
      return unless header&.fetch("type", nil) == "session"

      stat = File.stat(path)
      project_path = header["cwd"].presence || Dir.home
      session_id = header["id"].presence || File.basename(path, ".jsonl")
      started_at = time_from(header["timestamp"]) || stat.mtime.in_time_zone

      SessionContext.new(
        session_id: session_id,
        title: header["name"].presence || "Pi: #{File.basename(project_path)}",
        project_path: project_path,
        started_at: started_at,
        updated_at: stat.mtime.in_time_zone,
        path: Pathname.new(path)
      )
    rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
      Rails.logger.debug("Pi session log skipped #{path}: #{error.class}: #{error.message}")
      nil
    end

    def events_for(context, running:)
      translator = RuntimeAdapters::PiJsonlTranslator.new(
        session_id: context.session_id,
        project_path: context.project_path,
        title: context.title,
        occurred_at: context.started_at
      )
      events = [
        {
          runtime_name: "pi",
          type: "session.started",
          event_id: "pi-session-log-#{context.session_id}-started",
          session_id: context.session_id,
          title: context.title,
          project_path: context.project_path,
          started_at: context.started_at.iso8601,
          last_seen_at: context.updated_at.iso8601,
          occurred_at: context.started_at.iso8601
        }
      ]

      each_json_record(context.path) do |record|
        next if record["type"] == "session"

        events.concat(translator.events_for(record))
      end

      unless running
        events << {
          runtime_name: "pi",
          type: "session.finished",
          event_id: "pi-session-log-#{context.session_id}-finished",
          session_id: context.session_id,
          title: context.title,
          project_path: context.project_path,
          started_at: context.started_at.iso8601,
          last_seen_at: context.updated_at.iso8601,
          occurred_at: context.updated_at.iso8601,
          status: "completed"
        }
      end

      events
    end

    def first_json_record(path)
      File.open(path, "rb") do |file|
        file.each_line do |line|
          next unless line.lstrip.start_with?("{")

          return JSON.parse(line)
        end
      end
      nil
    end

    def each_json_record(path)
      return enum_for(:each_json_record, path) unless block_given?

      File.open(path, "rb") do |file|
        file.each_line do |line|
          next unless line.lstrip.start_with?("{")

          yield JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end
    rescue Errno::ENOENT, Errno::EACCES => error
      Rails.logger.debug("Pi session log skipped #{path}: #{error.class}: #{error.message}")
    end

    def running_session_ids_for(contexts)
      active_paths = active_paths_for_scan
      return Set.new if active_paths.empty?

      contexts
        .group_by(&:project_path)
        .filter_map { |project_path, project_sessions| project_sessions.max_by(&:updated_at)&.session_id if active_paths.include?(project_path) }
        .to_set
    end

    def active_paths_for_scan
      paths = active_project_paths || process_scanner.sessions.map(&:cwd)
      paths.compact.to_set
    rescue StandardError => error
      Rails.logger.debug("Pi active process scan skipped: #{error.class}: #{error.message}")
      Set.new
    end

    def time_from(value)
      return if value.blank?

      numeric = Float(value, exception: false)
      return Time.zone.at(numeric > 10_000_000_000 ? numeric / 1_000.0 : numeric) if numeric

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
