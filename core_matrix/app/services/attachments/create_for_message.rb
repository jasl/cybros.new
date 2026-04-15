module Attachments
  class CreateForMessage
    include Rails.application.routes.url_helpers

    DEFAULT_MAX_BYTES = 100.megabytes
    DEFAULT_MAX_COUNT = 10
    DEFAULT_NATIVE_FILE_MAX_BYTES = 1.megabyte
    DEFAULT_SIGNED_URL_EXPIRES_IN = 5.minutes
    VALID_PUBLICATION_ROLES = %w[primary_deliverable source_bundle preview evidence].freeze

    LimitExceeded = Class.new(StandardError) do
      attr_reader :reason

      def initialize(reason:)
        @reason = reason
        super(reason)
      end
    end

    InvalidParameters = Class.new(StandardError) do
      attr_reader :reason

      def initialize(reason:)
        @reason = reason
        super(reason)
      end
    end

    AttachmentTooLarge = Class.new(LimitExceeded)
    AttachmentCountExceeded = Class.new(LimitExceeded)

    def self.call(...)
      new(...).call
    end

    def self.default_max_bytes
      configured_positive_integer(:max_bytes, DEFAULT_MAX_BYTES)
    end

    def self.default_max_count
      configured_positive_integer(:max_count, DEFAULT_MAX_COUNT)
    end

    def self.native_file_max_bytes
      configured_positive_integer(:native_file_max_bytes, DEFAULT_NATIVE_FILE_MAX_BYTES)
    end

    def self.signed_url_expires_in
      configured_duration(:signed_url_expires_in, DEFAULT_SIGNED_URL_EXPIRES_IN)
    end

    def self.publication_role_for(attachment)
      attachment.file.blob.metadata["publication_role"].presence
    end

    def self.source_kind_for(attachment)
      attachment.file.blob.metadata["source_kind"].presence
    end

    def self.native_delivery?(attachment:, descriptor:)
      return true if descriptor["modality"] == "image"
      return true if descriptor["attachment_id"].blank?

      attachment.file.blob.byte_size < native_file_max_bytes
    end

    def self.signed_download_url(attachment:, host:)
      Rails.application.routes.url_helpers.rails_storage_redirect_url(
        attachment.file,
        **normalize_url_options(host).merge(expires_in: signed_url_expires_in)
      )
    end

    def self.normalize_url_options(host)
      case host
      when String
        { host: host }
      when Hash
        host.symbolize_keys
      else
        Rails.application.routes.default_url_options.presence ||
          ActionMailer::Base.default_url_options
      end
    end

    def self.configured_positive_integer(key, default)
      value = configuration_value(key).to_i
      value.positive? ? value : default
    end

    def self.configured_duration(key, default)
      value = configuration_value(key)
      return value if value.respond_to?(:to_i) && value.to_i.positive?

      default
    end

    def self.configuration_value(key)
      config = Rails.configuration.x.respond_to?(:attachments) ? Rails.configuration.x.attachments : nil
      return if config.blank?
      return config[key] if config.respond_to?(:[])
      return config.public_send(key) if config.respond_to?(key)

      nil
    end

    def initialize(message:, files:, source_kind: nil, publication_role: nil, max_bytes: self.class.default_max_bytes, max_count: self.class.default_max_count)
      @message = message
      @files = Array(files)
      @source_kind = source_kind
      @publication_role = publication_role
      @max_bytes = max_bytes
      @max_count = max_count
    end

    def call
      validate_publication_role!(@publication_role) if @publication_role.present?
      normalized_files = @files.map { |file| normalize_file(file) }
      enforce_count!(normalized_files)
      enforce_size!(normalized_files)
      created_blobs = []

      MessageAttachment.transaction do
        normalized_files.map { |file| create_attachment!(file, created_blobs: created_blobs) }
      end
    rescue StandardError
      created_blobs&.each do |blob|
        blob.purge if blob.present? && blob.persisted?
      end
      raise
    end

    private

    def normalize_file(file)
      if uploaded_file?(file)
        {
          io: file.tempfile,
          filename: file.original_filename,
          content_type: file.content_type,
          byte_size: file.size,
          identify: false,
          metadata: {},
          publication_role: @publication_role
        }
      elsif file.is_a?(Hash)
        normalize_hash_file(file.deep_symbolize_keys)
      else
        raise ArgumentError, "unsupported attachment source: #{file.class.name}"
      end
    end

    def normalize_hash_file(file)
      publication_role = file[:publication_role].presence || @publication_role
      validate_publication_role!(publication_role) if publication_role.present?

      {
        io: file[:io],
        path: file[:path],
        filename: file.fetch(:filename),
        content_type: file[:content_type],
        byte_size: file[:byte_size] || byte_size_for(file),
        identify: file.key?(:identify) ? file[:identify] : false,
        metadata: file.fetch(:metadata, {}).deep_stringify_keys,
        publication_role: publication_role,
        origin_attachment: file[:origin_attachment],
        origin_message: file[:origin_message]
      }
    end

    def byte_size_for(file)
      return File.size(file.fetch(:path)) if file[:path].present?

      io = file[:io]
      return io.size if io.respond_to?(:size)

      io.to_s.bytesize
    end

    def uploaded_file?(file)
      return true if file.is_a?(ActionDispatch::Http::UploadedFile)
      return true if defined?(Rack::Test::UploadedFile) && file.is_a?(Rack::Test::UploadedFile)

      false
    end

    def validate_publication_role!(publication_role)
      return if VALID_PUBLICATION_ROLES.include?(publication_role)

      raise InvalidParameters.new(reason: "invalid_publication_role")
    end

    def enforce_count!(files)
      return if files.length <= @max_count

      raise AttachmentCountExceeded.new(reason: "attachment_count_exceeded")
    end

    def enforce_size!(files)
      oversize = files.find { |file| file.fetch(:byte_size).to_i > @max_bytes }
      return if oversize.blank?

      raise AttachmentTooLarge.new(reason: "attachment_too_large")
    end

    def create_attachment!(file, created_blobs:)
      attachment = MessageAttachment.new(
        installation: @message.installation,
        conversation: @message.conversation,
        message: @message,
        origin_attachment: file[:origin_attachment],
        origin_message: file[:origin_message]
      )

      io, autoclose = open_io(file)
      io.rewind if io.respond_to?(:rewind)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: file.fetch(:filename),
        content_type: file[:content_type],
        metadata: attachment_metadata(file),
        identify: file.fetch(:identify)
      )
      created_blobs << blob
      attachment.file.attach(blob)
      attachment.save!
      attachment
    ensure
      io&.close if autoclose
    end

    def open_io(file)
      if file[:path].present?
        [File.open(file.fetch(:path), "rb"), true]
      else
        [file.fetch(:io), false]
      end
    end

    def attachment_metadata(file)
      file.fetch(:metadata).merge(
        {
          "publication_role" => file[:publication_role],
          "source_kind" => @source_kind
        }.compact
      )
    end
  end
end
