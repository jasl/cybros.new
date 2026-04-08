require "timeout"

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
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
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

    wait_for_parallel_signals!(ready, operations.size, deadline)
    operations.size.times { gate << true }

    threads.each do |thread|
      raise "parallel operation timed out" if thread.join(remaining_parallel_timeout(deadline)).nil?
    end

    results
  ensure
    Array(threads).each do |thread|
      next unless thread&.alive?

      thread.kill
      thread.join
    end
  end

  def wait_for_parallel_signals!(queue, count, deadline)
    Timeout.timeout(remaining_parallel_timeout(deadline), RuntimeError, "parallel operation timed out") do
      count.times { queue.pop }
    end
  end

  def remaining_parallel_timeout(deadline)
    [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
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
      tables = (connection.tables - %w[schema_migrations ar_internal_metadata]).sort
      return if tables.empty?

      quoted_tables = tables.map { |table| connection.quote_table_name(table) }.join(", ")
      connection.execute("TRUNCATE TABLE #{quoted_tables} RESTART IDENTITY CASCADE")
    end
  end

  def delete_all_table_rows!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      tables = connection.tables - %w[schema_migrations ar_internal_metadata]

      connection.disable_referential_integrity do
        tables.each do |table|
          connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
        end
      end
    end
  end
end
