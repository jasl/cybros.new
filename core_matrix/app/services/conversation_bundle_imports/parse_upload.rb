require "json"
require "zip"

module ConversationBundleImports
  class ParseUpload
    def self.call(...)
      new(...).call
    end

    def initialize(request:)
      @request = request
    end

    def call
      entries = {}

      Zip::File.open_buffer(StringIO.new(@request.upload_file.download)) do |zip_file|
        zip_file.each do |entry|
          next if entry.directory?

          entries[entry.name] = entry.get_input_stream.read
        end
      end

      {
        "entries" => entries,
        "manifest" => JSON.parse(entries.fetch("manifest.json")),
        "conversation_payload" => JSON.parse(entries.fetch("conversation.json")),
        "file_bytes" => entries.select { |name, _| name.start_with?("files/") },
      }
    end
  end
end
