require "fileutils"
require "securerandom"

class MachineBridge
  HEADER = "X-Agent-Passports-Machine-Token"
  CONFIG_DIR = ".config/agent-passports"
  TOKEN_FILE = "machine-token"
  SERVER_URL_FILE = "server-url"

  class << self
    def token
      return "test-machine-token" if Rails.env.test? && ENV["AGENT_PASSPORTS_MACHINE_TOKEN"].blank?

      ENV["AGENT_PASSPORTS_MACHINE_TOKEN"].presence || token_from_file
    end

    def valid_token?(candidate)
      candidate.present? &&
        token.present? &&
        candidate.bytesize == token.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(candidate, token)
    end

    def token_path
      configured = ENV["AGENT_PASSPORTS_MACHINE_TOKEN_PATH"].presence
      return Pathname.new(configured).expand_path if configured
      return Rails.root.join("tmp", "agent-passports-test-machine-token") if Rails.env.test?

      Pathname.new(Dir.home).join(CONFIG_DIR, TOKEN_FILE)
    end

    def server_url_path
      configured = ENV["AGENT_PASSPORTS_SERVER_URL_PATH"].presence
      return Pathname.new(configured).expand_path if configured
      return Rails.root.join("tmp", "agent-passports-test-server-url") if Rails.env.test?

      Pathname.new(Dir.home).join(CONFIG_DIR, SERVER_URL_FILE)
    end

    private

    def token_from_file
      ensure_token_file!
      token_path.read.strip
    end

    def ensure_token_file!
      return if token_path.exist?

      FileUtils.mkdir_p(token_path.dirname, mode: 0700)
      token_path.write(SecureRandom.urlsafe_base64(32))
      File.chmod(0600, token_path)
    end
  end
end
