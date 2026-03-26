module AgentControl
  class StreamName
    def self.for_deployment(deployment)
      "agent_control:deployment:#{deployment.public_id}"
    end
  end
end
