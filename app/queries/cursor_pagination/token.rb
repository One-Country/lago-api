# frozen_string_literal: true

module CursorPagination
  # Opaque cursor: Base64URL of `{"v": version, "o": {"t": table, "s": sort}, "k": key}`,
  # the key holding one value per sort column, in the order of the sort.
  #
  # It is not signed. Every query is scoped to the organization of the API key, so a
  # forged cursor only repositions its caller within their own data. It is validated
  # strictly instead, so that a bad cursor is a 400 and never reaches Postgres.
  module Token
    VERSION = 1
    MAX_LENGTH = 512
    ENCODED_FORMAT = /\A[A-Za-z0-9_-]+\z/
    TIMESTAMP_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    # How each sort column is written in a key, and read back as the type the column
    # compares with: a date stays a `Date`, so a timestamp cannot be resumed as one.
    Column = Data.define(:format, :dump, :load)
    COLUMNS = {
      created_at: Column.new(TIMESTAMP_FORMAT, ->(time) { time.utc.iso8601(6) }, ->(value) { Time.iso8601(value) }),
      issuing_date: Column.new(DATE_FORMAT, ->(date) { date.iso8601 }, ->(value) { Date.iso8601(value) }),
      id: Column.new(BaseQuery::UUID_REGEX, ->(id) { id }, ->(value) { value })
    }.freeze

    def self.encode(table:, record:, sort: DEFAULT_SORT)
      CursorPagination.validate_sort!(sort)

      payload = {
        v: VERSION,
        o: {t: table, s: CursorPagination.signature(sort)},
        k: sort.keys.map { |column| COLUMNS.fetch(column).dump.call(record.public_send(column)) }
      }

      Base64.urlsafe_encode64(payload.to_json, padding: false)
    end

    # Returns the key of the anchor row, one typed value per sort column. `param` names
    # the request parameter the value came from, to key the error details.
    def self.decode(value, table:, param:, sort: DEFAULT_SORT)
      CursorPagination.validate_sort!(sort)
      invalid = ->(reason) { raise Error.new(code: Error::INVALID_CURSOR, details: {param => {reason:}}) }

      # A request parameter can also arrive as an array or a hash (`after[]=`, `after[k]=`).
      invalid.call("malformed") unless value.is_a?(String)
      invalid.call("too_long") if value.bytesize > MAX_LENGTH
      invalid.call("malformed") unless value.match?(ENCODED_FORMAT)

      payload = parse(value)
      invalid.call("malformed") unless payload.is_a?(Hash) && payload.keys.sort == %w[k o v]
      invalid.call("unsupported_version") unless payload["v"].eql?(VERSION)

      ordering = payload["o"]
      invalid.call("malformed") unless ordering.is_a?(Hash) && ordering.keys.sort == %w[s t]
      invalid.call("wrong_resource") unless ordering["t"] == table

      if ordering["s"] != CursorPagination.signature(sort)
        raise Error.new(code: Error::CURSOR_EXPIRED, details: {param => {reason: "sort_changed"}})
      end

      key(payload["k"], sort) || invalid.call("malformed_key")
    end

    def self.parse(value)
      JSON.parse(Base64.urlsafe_decode64(value))
    rescue ArgumentError, EncodingError, JSON::ParserError
      nil
    end
    private_class_method :parse

    def self.key(values, sort)
      return unless values.is_a?(Array) && values.size == sort.size

      keys = sort.keys.zip(values).map do |column, value|
        type = COLUMNS.fetch(column)
        next unless value.is_a?(String) && value.match?(type.format)

        type.load.call(value)
      end
      keys unless keys.include?(nil)
    rescue ArgumentError
      # A well-shaped but impossible date or timestamp, like month 13.
      nil
    end
    private_class_method :key
  end
end
