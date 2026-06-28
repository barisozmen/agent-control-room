require "test_helper"

class RuntimeAdapters::PiProcessScannerTest < ActiveSupport::TestCase
  SuccessStatus = Struct.new(:success?) do
    def success?
      self[:success?]
    end
  end

  FakeRunner = Struct.new(:outputs) do
    def call(*command)
      [ outputs.fetch(command), SuccessStatus.new(true) ]
    end
  end

  test "discovers live pi cli sessions with their cwd" do
    ps_output = <<~PS
       101 Sat Jun 27 17:36:49 2026 pi
       202 Sat Jun 27 17:37:36 2026 /opt/homebrew/bin/pi install npm:@example/pkg
       303 Sat Jun 27 17:38:02 2026 pi --version
    PS
    runner = FakeRunner.new(
      {
        [ "ps", "-axo", "pid=,lstart=,command=" ] => ps_output,
        [ "lsof", "-a", "-p", "101", "-d", "cwd", "-Fn" ] => "p101\nfcwd\nn#{Rails.root}\n"
      }
    )

    scanner = RuntimeAdapters::PiProcessScanner.new(command_runner: runner, timeout_seconds: 0.1)
    session = scanner.sessions.sole
    event = session.to_runtime_event

    assert_equal "pi", session.runtime_name
    assert_equal 101, session.pid
    assert_equal Rails.root.to_s, session.cwd
    assert_equal "session.started", event.fetch(:type)
    assert_equal "pi-process-101-#{Time.zone.parse("Sat Jun 27 17:36:49 2026").to_i}", event.fetch(:session_id)
    assert_equal "Pi", event.fetch(:title)
    assert_equal 101, event.fetch(:pid)
  end
end
