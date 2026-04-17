require "test_helper"

class MemoryStoreTest < Minitest::Test
  def test_writes_session_memory_under_nexus_home_and_reads_combined_summary
    workspace_root = tmp_path("workspace")
    FileUtils.mkdir_p(workspace_root)
    File.write(File.join(workspace_root, "MEMORY.md"), "Workspace memory")

    store = CybrosNexus::Memory::Store.new(
      workspace_root: workspace_root,
      conversation_id: "conv_123",
      home_root: tmp_path("nexus-home")
    )

    result = store.write("summary.md", "Session summary")

    assert_equal "Session summary", result.fetch("content")
    assert_equal "Workspace memory", store.root_memory
    assert_equal "Session summary", store.session_summary
    assert_includes store.session_summary_path.to_s, "nexus-home"
    assert_equal(
      {
        "root_memory" => "Workspace memory",
        "session_summary" => "Session summary",
        "summary" => "Workspace memory\n\nSession summary",
      },
      store.summary_payload
    )
  end
end
