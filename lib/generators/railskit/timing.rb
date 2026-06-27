# frozen_string_literal: true

module Railskit
  module Timing
    @timings = []

    class << self
      attr_reader :timings

      def measure(label)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        @timings << [ label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start ] if start
      end

      def report
        return if timings.empty?
        puts "\n" + "=" * 70
        puts " TIMING REPORT"
        puts "=" * 70
        timings.each { |label, duration| puts "%8.2fs  %s" % [ duration, label ] }
        puts "-" * 70
        puts "%8.2fs  TOTAL" % timings.sum(&:last)
        puts "=" * 70 + "\n"
      end
    end
  end

  module TimedActions
    def generate(what, *args, &block)
      Railskit::Timing.measure(what) { super }
    end

    def rails_command(command, *args, &block)
      # Skip timing for "generate" - it's timed by the generate method
      return super if command.to_s.start_with?("generate ")
      Railskit::Timing.measure("rails #{command}") { super }
    end

    def run(command, *args, &block)
      # Only time bundle install explicitly - other run calls pass through
      if command.include?("bundle install")
        Railskit::Timing.measure("bundle install") { super }
      else
        super
      end
    end

    def git(command)
      return if ENV["SKIP_COMMITS"] == "1" && command.is_a?(Hash) && (command[:add] || command[:commit])
      super
    end
  end
end

# Prepend to Rails::Generators::Actions (where generate/rails_command are defined)
Rails::Generators::Actions.prepend(Railskit::TimedActions)
# Also prepend to Thor::Actions for run/git
Thor::Actions.prepend(Railskit::TimedActions)
