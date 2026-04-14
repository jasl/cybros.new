class AddRequestPreparationContractDocumentToAgentDefinitionVersions < ActiveRecord::Migration[8.0]
  class MigrationAgentDefinitionVersion < ApplicationRecord
    self.table_name = "agent_definition_versions"
  end

  class MigrationJsonDocument < ApplicationRecord
    self.table_name = "json_documents"
  end

  def up
    add_reference :agent_definition_versions, :request_preparation_contract_document, foreign_key: { to_table: :json_documents }, null: true

    MigrationAgentDefinitionVersion.reset_column_information

    MigrationAgentDefinitionVersion.find_each do |agent_definition_version|
      payload = {}
      serialized_payload = JSON.generate(payload)
      content_sha256 = Digest::SHA256.hexdigest(serialized_payload)

      document = MigrationJsonDocument.find_or_create_by!(
        installation_id: agent_definition_version.installation_id,
        document_kind: "agent_request_preparation_contract",
        content_sha256: content_sha256
      ) do |json_document|
        json_document.payload = payload
        json_document.content_bytesize = serialized_payload.bytesize
      end

      agent_definition_version.update_columns(request_preparation_contract_document_id: document.id)
    end

    change_column_null :agent_definition_versions, :request_preparation_contract_document_id, false
  end

  def down
    remove_reference :agent_definition_versions, :request_preparation_contract_document, foreign_key: { to_table: :json_documents }
  end
end
