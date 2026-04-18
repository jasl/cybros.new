# frozen_string_literal: true

module Verification
  module CapstoneAppApiRoundtrip
    module_function

    def prompt(generated_app_dir:)
      <<~PROMPT
        No screenshots or visual design review are needed.
        You must still start the app and verify it in a browser session.
        The design is approved.
        Proceed autonomously now without asking more questions unless you are genuinely blocked.

        Build a complete browser-playable React 2048 game in `#{generated_app_dir}`.

        Requirements:
        - use modern React + Vite + TypeScript
        - implement real 2048 rules: movement, merging, random tile spawning, score tracking, win/game-over behavior, and restart
        - support both arrow keys and WASD
        - add automated tests for the game logic
        - run the tests and production build successfully
        - ensure the final Vite/Vitest configuration keeps `npm run build` passing
        - if you edit `package.json`, lockfiles, or TypeScript/Vite config, keep the dependency manifest self-consistent, rerun `npm install` before the final `npm run build`, and the build must still pass after that reinstall
        - preserve scaffolded dependencies required by the Vite TypeScript template, including Node type support when `tsconfig.node.json` references `"node"`
        - start the app on `0.0.0.0:4173`
        - verify it in a browser session
        - end with a concise completion note that reflects what actually passed

        Runtime process requirements:
        - when you need a long-running server, use the runtime background-process tool instead of `nohup`, `python -m http.server`, or any foreground shell command that keeps the tool call open
        - use only non-interactive shell commands with no attached TTY session; do not create interactive command sessions or use follow-up wait tools for shell inspection
        - do not start a second dev server if one is already running on `0.0.0.0:4173`
        - keep the browser verification pointed at the background process that serves the app on `0.0.0.0:4173`
        - do not introduce extra preview or proxy servers unless you are genuinely blocked

        Verification harness requirements:
        - render the board as a visible 4x4 grid with exactly 16 cells
        - expose the board with `data-testid="board"` and `role="grid"` with an accessible name containing `2048 board`
        - expose each cell with `role="gridcell"`
        - expose score with `data-testid="score"`
        - expose game status text with `data-testid="status"`
        - expose a game-over status through `data-testid="status"` that visibly contains the words `Game over` when no moves remain
        - expose restart or new-game control with `data-testid="restart"`
      PROMPT
    end

    def registration_artifact(agent_definition_version:, execution_runtime:, agent_connection_credential:, onboarding_session_id:)
      {
        "agent_id" => agent_definition_version.agent.public_id,
        "agent_display_name" => agent_definition_version.agent.display_name,
        "agent_definition_version_id" => agent_definition_version.public_id,
        "execution_runtime_id" => execution_runtime.public_id,
        "execution_runtime_display_name" => execution_runtime.display_name,
        "execution_runtime_fingerprint" => execution_runtime.execution_runtime_fingerprint,
        "onboarding_session_id" => onboarding_session_id,
        "agent_connection_credential_redacted" => redact(agent_connection_credential)
      }
    end

    def run_bootstrap_artifact(scenario_date:, selector:, workspace_root:, generated_app_dir:, prompt:)
      {
        "scenario_date" => scenario_date,
        "selector" => selector,
        "workspace_root" => workspace_root.to_s,
        "generated_app_dir" => generated_app_dir.to_s,
        "prompt" => prompt
      }
    end

    def redact(secret)
      return "[missing]" if secret.blank?
      return "*" * secret.length if secret.length <= 8

      "#{secret[0, 4]}...#{secret[-4, 4]}"
    end
  end
end
