module ConcurrentAllocationHelpers
  ParallelResult = Struct.new(:value, :error, keyword_init: true)

  private

  def run_in_parallel(count = nil, timeout: 10, &block)
    raise ArgumentError, "count must be provided when using a block" if block.present? && count.blank?

    operations = if block.present?
      Array.new(count) { |index| proc { block.call(index) } }
    else
      Array(count)
    end

    run_parallel_operations(*operations, timeout: timeout)
  end

  def run_parallel_operations(*operations, timeout: 10)
    ready = Queue.new
    gate = Queue.new
    results = Array.new(operations.size)

    threads = operations.each_with_index.map do |operation, index|
      Thread.new do
        Thread.current.report_on_exception = false

        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          results[index] = ParallelResult.new(value: operation.call)
        rescue => error
          results[index] = ParallelResult.new(error: error)
        end
      end
    end

    operations.size.times { ready.pop }
    operations.size.times { gate << true }

    threads.each do |thread|
      raise "parallel operation timed out" if thread.join(timeout).nil?
    end

    results
  end

  def assert_parallel_success!(results)
    errors = results.filter_map(&:error)

    assert_empty(
      errors,
      errors.map { |error| "#{error.class}: #{error.message}" }.join("\n")
    )

    results.map(&:value)
  end

  def truncate_all_tables!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      tables = connection.tables - %w[schema_migrations ar_internal_metadata]

      connection.disable_referential_integrity do
        tables.each do |table|
          connection.execute("TRUNCATE TABLE #{connection.quote_table_name(table)} RESTART IDENTITY CASCADE")
        end
      end
    end
  end
end
