require "digest"

module RuntimeAdapters
  class PiJsonlTranslator
    SENSITIVE_KEY_PATTERN = /(authorization|cookie|password|secret|token|api[_-]?key|credential)/i
    MAX_STRING_LENGTH = 1_200

    def initialize(session_id: nil, project_path: nil, title: nil, occurred_at: nil)
      @session_id = session_id
      @project_path = project_path
      @title = title
      @occurred_at = occurred_at
    end

    def events_for(record)
      record = record.with_indifferent_access
      @occurred_at = parsed_time(record[:timestamp]) || timestamp_from_message(record[:message]) || @occurred_at || Time.current

      case record[:type]
      when "session" then session_header_event(record)
      when "tool_execution_start" then [ observed_tool_event(record, source_event_id: request_event_id(record[:toolCallId]), status: "running") ].compact
      when "tool_execution_end" then [ finished_tool_event(record, source_event_id: request_event_id(record[:toolCallId])) ].compact
      when "agent_end" then [ session_finished_event(record) ]
      when "message" then message_events(record)
      else
        []
      end
    end

    def self.sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, inner), sanitized|
          sanitized[key] = key.to_s.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : sanitize(inner)
        end
      when Array
        value.map { |inner| sanitize(inner) }
      when String
        value.length > MAX_STRING_LENGTH ? "#{value.first(MAX_STRING_LENGTH)}... [truncated]" : value
      else
        value
      end
    end

    private

    attr_reader :session_id, :project_path, :title, :occurred_at

    def session_header_event(record)
      @session_id = record[:id].presence || session_id
      @project_path = record[:cwd].presence || project_path
      @title = record[:name].presence || pi_title(project_path)

      [ base_event("session.started", event_id: "#{event_prefix}-session-started") ]
    end

    def session_finished_event(record)
      base_event(
        "session.finished",
        event_id: "#{event_prefix}-session-finished",
        status: record[:status].presence || "completed"
      )
    end

    def message_events(record)
      message = record.fetch(:message, {}).with_indifferent_access

      case message[:role]
      when "assistant" then assistant_tool_call_events(record, message)
      when "toolResult" then [ tool_result_event(record, message) ].compact
      when "bashExecution" then bash_execution_events(record, message)
      else
        []
      end
    end

    def assistant_tool_call_events(record, message)
      Array(message[:content]).filter_map do |content|
        content = content.with_indifferent_access
        next unless content[:type] == "toolCall"

        observed_tool_event(
          {
            toolCallId: content[:id],
            toolName: content[:name],
            args: content[:arguments],
            entry_id: record[:id]
          }.with_indifferent_access,
          source_event_id: request_event_id(content[:id] || record[:id]),
          status: "running"
        )
      end
    end

    def tool_result_event(record, message)
      tool_call_id = message[:toolCallId].presence || record[:id]
      finished_tool_event(
        {
          toolCallId: tool_call_id,
          toolName: message[:toolName],
          result: message,
          isError: message[:isError]
        }.with_indifferent_access,
        source_event_id: request_event_id(tool_call_id)
      )
    end

    def bash_execution_events(record, message)
      source_event_id = request_event_id(record[:id])
      raw = {
        toolCallId: record[:id],
        toolName: "bash",
        args: { command: message[:command] },
        result: message,
        isError: message[:exitCode].present? && message[:exitCode].to_i != 0
      }.with_indifferent_access

      [
        observed_tool_event(raw, source_event_id: source_event_id, status: "running"),
        finished_tool_event(raw, source_event_id: source_event_id)
      ].compact
    end

    def observed_tool_event(raw, source_event_id:, status:)
      tool_name = raw[:toolName].presence || "tool"
      args = raw[:args].presence || raw[:arguments].presence || {}
      args = args.respond_to?(:with_indifferent_access) ? args.with_indifferent_access : {}.with_indifferent_access
      details = details_for(tool_name, args)

      base_event(
        "tool.observed",
        event_id: source_event_id,
        actor_ref: "main-agent",
        capability: details.fetch(:capability),
        action_kind: details.fetch(:action_kind),
        action_summary: details.fetch(:action_summary),
        command: details[:command],
        path: details[:path],
        status: status,
        observation_mode: "posthoc",
        raw_event: self.class.sanitize(raw)
      )
    end

    def finished_tool_event(raw, source_event_id:)
      tool_name = raw[:toolName].presence || "tool"
      args = raw[:args].presence || {}
      args = args.respond_to?(:with_indifferent_access) ? args.with_indifferent_access : {}.with_indifferent_access
      details = details_for(tool_name, args)

      base_event(
        "tool.finished",
        event_id: "#{source_event_id}-finished",
        source_event_id: source_event_id,
        actor_ref: "main-agent",
        capability: details.fetch(:capability),
        action_kind: details.fetch(:action_kind),
        action_summary: "Pi #{tool_name} completed",
        exit_status: exit_status_from(raw),
        observation_mode: "posthoc",
        raw_event: self.class.sanitize(raw)
      )
    end

    def details_for(tool_name, args)
      case tool_name.to_s
      when "bash"
        command = args[:command].presence || args[:cmd].presence
        {
          capability: "bash",
          action_kind: "shell_command",
          action_summary: command.presence || "Pi bash command",
          command: command
        }
      when "write", "edit"
        path = args[:path].presence || args[:file].presence
        {
          capability: "edit",
          action_kind: "file_edit",
          action_summary: path.present? ? "Pi #{tool_name}: #{path}" : "Pi #{tool_name}",
          path: path
        }
      when "read", "grep", "find", "ls"
        path = args[:path].presence || args[:directory].presence || args[:pattern].presence
        {
          capability: "read",
          action_kind: tool_name.to_s,
          action_summary: path.present? ? "Pi #{tool_name}: #{path}" : "Pi #{tool_name}",
          path: path
        }
      else
        {
          capability: "web",
          action_kind: tool_name.to_s,
          action_summary: "Pi #{tool_name}"
        }
      end
    end

    def base_event(type, **attributes)
      {
        runtime_name: "pi",
        type: type,
        session_id: session_id,
        title: title.presence || pi_title(project_path),
        project_path: project_path.presence || Dir.pwd,
        occurred_at: occurred_at.iso8601
      }.merge(attributes.compact)
    end

    def request_event_id(id)
      "#{event_prefix}-#{id.presence || "unknown"}-requested"
    end

    def event_prefix
      "pi-jsonl-#{session_id.presence || Digest::SHA256.hexdigest("#{project_path}:#{title}")[0, 16]}"
    end

    def pi_title(path)
      basename = path.present? ? File.basename(path.to_s) : nil
      basename.present? ? "Pi: #{basename}" : "Pi"
    end

    def timestamp_from_message(message)
      return unless message.respond_to?(:[])

      value = message.with_indifferent_access[:timestamp]
      return if value.blank?

      numeric = Float(value, exception: false)
      return Time.zone.at(numeric > 10_000_000_000 ? numeric / 1_000.0 : numeric) if numeric

      parsed_time(value)
    end

    def parsed_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def exit_status_from(raw)
      return 1 if raw[:isError] == true

      result = raw[:result]
      result = result.with_indifferent_access if result.respond_to?(:with_indifferent_access)
      result&.[](:exitCode)
    end
  end
end
