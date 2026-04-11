# frozen_string_literal: true

module Acceptance
  # Shared prompt and artifact payload builders for the Fenix capstone scenario.
  module CapstoneAppApiRoundtrip
    module_function

    def prompt(generated_app_dir:)
      <<~PROMPT
        No screenshots or visual design review are needed.
        You must still start the app and verify it in a browser session.
        The design is approved.
        Proceed autonomously now without asking more questions unless you are genuinely blocked.
        Use the runtime's built-in planning, tool use, and delegation behavior. Do not rely on staged workflow bootstrap skills.

        Build a complete browser-playable React 2048 game in `#{generated_app_dir}`.

        Requirements:
        - use modern React + Vite + TypeScript
        - implement real 2048 rules: movement, merging, random tile spawning, score tracking, win/game-over behavior, and restart
        - support both arrow keys and WASD
        - add automated tests for the game logic
        - run the tests and production build successfully
        - ensure the final Vite/Vitest configuration keeps `npm run build` passing
        - start the app on `0.0.0.0:4173`
        - verify it in a browser session
        - use subagents when genuinely helpful
        - end with a concise completion note

        Acceptance harness requirements:
        - render the board as a visible 4x4 grid with exactly 16 cells
        - expose the board with `data-testid="board"` and `role="grid"` with an accessible name containing `2048 board`
        - expose each cell with `role="gridcell"`
        - expose score with `data-testid="score"`
        - expose game status text with `data-testid="status"`
        - expose a game-over status through `data-testid="status"` that visibly contains the words `Game over` when no moves remain
        - if the board reaches a terminal no-moves state, the visible status must contain the exact words `Game over`
        - expose restart or new-game control with `data-testid="restart"`
      PROMPT
    end

    def bootstrap_state(**data)
      {
        'scenario_date' => data.fetch(:scenario_date),
        'agent_connection_credential' => data.fetch(:agent_connection_credential),
        'execution_runtime_connection_credential' => data.fetch(:execution_runtime_connection_credential)
      }.merge(bootstrap_public_ids(data)).merge(bootstrap_runtime_metadata(data))
    end

    def registration_artifact(**data)
      {
        'agent_id' => data.fetch(:agent).public_id,
        'agent_display_name' => data.fetch(:agent).display_name,
        'agent_snapshot_id' => data.fetch(:agent_snapshot).public_id,
        'execution_runtime_id' => data.fetch(:execution_runtime).public_id,
        'execution_runtime_display_name' => data.fetch(:execution_runtime).display_name,
        'execution_runtime_fingerprint' => data.fetch(:execution_runtime).execution_runtime_fingerprint,
        'agent_fingerprint' => data.fetch(:agent_snapshot).fingerprint,
        'agent_connection_credential_redacted' => Acceptance::CredentialRedaction.redact(data.fetch(:agent_connection_credential))
      }
    end

    def run_bootstrap_artifact(**data)
      {
        'scenario_date' => data.fetch(:scenario_date),
        'operator' => data.fetch(:operator_name),
        'selector' => data.fetch(:selector),
        'attempt_count' => 0,
        'workspace_root' => data.fetch(:workspace_root).to_s,
        'generated_app_dir' => data.fetch(:generated_app_dir).to_s,
        'prompt' => data.fetch(:prompt)
      }
    end

    def bootstrap_public_ids(data)
      {
        'agent_id' => data.fetch(:agent).public_id,
        'agent_snapshot_id' => data.fetch(:agent_snapshot).public_id,
        'execution_runtime_id' => data.fetch(:execution_runtime).public_id,
        'agent_connection_id' => data.fetch(:agent_connection).public_id,
        'execution_runtime_connection_id' => data.fetch(:execution_runtime_connection).public_id
      }
    end

    def bootstrap_runtime_metadata(data)
      {
        'runtime_base_url' => data.fetch(:runtime_base_url),
        'docker_container' => data.fetch(:docker_container),
        'execution_runtime_fingerprint' => data.fetch(:execution_runtime_fingerprint),
        'agent_fingerprint' => data.fetch(:agent_fingerprint)
      }
    end

    private_class_method :bootstrap_public_ids, :bootstrap_runtime_metadata
  end
end
