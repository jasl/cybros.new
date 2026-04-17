module CybrosNexus
  module Browser
    class SessionRegistry
      def initialize
        @sessions = {}
        @mutex = Mutex.new
      end

      def store(session)
        @mutex.synchronize do
          @sessions[session.browser_session_id] = session
        end
        session
      end

      def lookup(key:)
        @mutex.synchronize { @sessions[key] }
      end

      def remove(key:)
        @mutex.synchronize { @sessions.delete(key) }
      end

      def project_list(runtime_owner_id: nil)
        sessions = @mutex.synchronize { @sessions.values.dup }
        filtered = if runtime_owner_id.nil? || runtime_owner_id.to_s.empty?
          sessions
        else
          sessions.select { |session| session.runtime_owner_id == runtime_owner_id }
        end

        return filtered unless block_given?

        filtered.map { |session| yield(session) }
      end

      def clear!
        @mutex.synchronize do
          sessions = @sessions.values
          @sessions = {}
          sessions
        end
      end
    end
  end
end
