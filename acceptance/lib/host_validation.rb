require "fileutils"
require "json"
require "net/http"
require "open3"
require "socket"
require "uri"

module Acceptance
  module HostValidation
    module_function

    DEFAULT_PLAYWRIGHT_VERSION = "1.59.1".freeze

    def run!(generated_app_dir:, artifact_dir:, preview_port:, runtime_validation:, persist_artifacts: true)
      host_validation_notes = []
      host_validation = {}
      playwright_validation = {}
      preview_http = nil
      host_playability_skip_reason = nil
      dist_artifact_present = false

      if generated_app_dir.exist?
        dist_dir = generated_app_dir.join("dist")
        dist_artifact_present = dist_dir.join("index.html").exist?
        if dist_artifact_present
          begin
            verification = run_host_preview_and_verification!(
              dist_dir: dist_dir,
              artifact_dir: artifact_dir,
              generated_app_dir: generated_app_dir,
              preview_port: preview_port
            )
            preview_http = verification.fetch("preview_http")
            playwright_validation = verification.fetch("playwright_validation")
          rescue => error
            host_playability_skip_reason = "Host-side browser verification failed against `dist/`: #{error.message}"
          end
        else
          host_playability_skip_reason = "Host-side browser verification did not run because `dist/index.html` was missing."
        end

        if generated_app_dir.join("node_modules").exist?
          FileUtils.rm_rf(generated_app_dir.join("node_modules"))
          host_validation_notes << "Removed container-built node_modules before source-portability diagnostics."
        end
        FileUtils.rm_rf(generated_app_dir.join("dist"))
        FileUtils.rm_rf(generated_app_dir.join("coverage"))

        npm_install = capture_command("npm", "install", chdir: generated_app_dir)
        npm_test = capture_command("npm", "test", chdir: generated_app_dir)
        npm_build = capture_command("npm", "run", "build", chdir: generated_app_dir)

        host_validation = {
          "npm_install" => npm_install,
          "npm_test" => npm_test,
          "npm_build" => npm_build,
          "preview_http" => preview_http,
        }

        if persist_artifacts
          write_json(artifact_dir.join("playable", "host-npm-install.json"), npm_install)
          write_json(artifact_dir.join("playable", "host-npm-test.json"), npm_test)
          write_json(artifact_dir.join("playable", "host-npm-build.json"), npm_build)
          write_json(artifact_dir.join("playable", "host-preview.json"), preview_http) if preview_http
          if playwright_validation.any?
            write_json(artifact_dir.join("playable", "host-playwright-install.json"), playwright_validation.fetch("install"))
            write_json(artifact_dir.join("playable", "host-playwright-test.json"), playwright_validation.fetch("test"))
          end

          write_text(artifact_dir.join("review", "workspace-validation.md"), <<~MD)
            # Workspace Validation

            Host-side source portability diagnostics:

            - `npm install` success: `#{npm_install.fetch("success")}`
            - `npm test` success: `#{npm_test.fetch("success")}`
            - `npm run build` success: `#{npm_build.fetch("success")}`

            Host-side `dist/` usability diagnostics:

            - `dist/index.html` present before host checks: `#{dist_artifact_present}`
            - static preview reachable: `#{preview_http&.fetch("status", nil) == 200}`
            - Playwright verification ran: `#{playwright_validation.any?}`
            - Playwright verification passed: `#{playwright_verification_passed?(playwright_validation)}`

            #{host_playability_skip_reason ? "Host playability note: #{host_playability_skip_reason}" : "Host playability note: browser verification used the exported `dist/` output."}

            See:

            - `playable/host-npm-install.json`
            - `playable/host-npm-test.json`
            - `playable/host-npm-build.json`
            #{preview_http ? "- `playable/host-preview.json`" : nil}
            #{playwright_validation.any? ? "- `playable/host-playwright-test.json`" : nil}
          MD

          write_playability_verification!(
            path: artifact_dir.join("review", "playability-verification.md"),
            playability_result: playwright_validation["result"],
            playwright_test: playwright_validation["test"],
            generated_app_dir: generated_app_dir,
            preview_port: preview_port,
            runtime_validation: runtime_validation,
            preview_validation: {
              "reachable" => preview_http&.fetch("status", nil) == 200,
              "contains_2048" => preview_http&.fetch("contains_2048", false) || false,
            },
            host_skip_reason: host_playability_skip_reason
          )
        end
      elsif persist_artifacts
        host_playability_skip_reason = "Generated application path was missing."
        write_text(artifact_dir.join("review", "workspace-validation.md"), <<~MD)
          # Workspace Validation

          Expected generated app directory was missing:
          - `#{generated_app_dir}`
        MD
        write_playability_verification!(
          path: artifact_dir.join("review", "playability-verification.md"),
          playability_result: nil,
          playwright_test: nil,
          generated_app_dir: generated_app_dir,
          preview_port: preview_port,
          runtime_validation: runtime_validation,
          preview_validation: {
            "reachable" => false,
            "contains_2048" => false,
          },
          host_skip_reason: host_playability_skip_reason
        )
      end

      {
        "host_validation_notes" => host_validation_notes,
        "host_validation" => host_validation,
        "playwright_validation" => playwright_validation,
        "preview_http" => preview_http,
        "host_playability_skip_reason" => host_playability_skip_reason,
        "dist_artifact_present" => dist_artifact_present,
      }
    end

    def write_playability_verification!(path:, playability_result:, playwright_test:, generated_app_dir:, preview_port:, runtime_validation:, preview_validation:, host_skip_reason: nil)
      unless playability_result
        lines = [
          "# Playability Verification",
          "",
          "## Conversation Runtime Evidence",
          "",
          "- Runtime-side build succeeded: `#{runtime_validation.fetch("runtime_build_passed")}`",
          "- Runtime-side test succeeded: `#{runtime_validation.fetch("runtime_test_passed")}`",
          "- Runtime-side dev server reached `:4173`: `#{runtime_validation.fetch("runtime_dev_server_ready")}`",
          "- Runtime-side browser session loaded content: `#{runtime_validation.fetch("runtime_browser_loaded")}`",
          "- Runtime browser content mentioned `2048`: `#{runtime_validation.fetch("runtime_browser_mentions_2048")}`",
        ]
        excerpt = runtime_validation.fetch("runtime_browser_content_excerpt").to_s
        unless excerpt.empty?
          lines.concat([
            "",
            "Runtime browser content excerpt:",
            "",
            "```text",
            excerpt,
            "```",
          ])
        end
        lines.concat([
          "",
          "## Host Playability Diagnostic",
          "",
          "- Host `dist/` preview reachable: `#{preview_validation.fetch("reachable")}`",
          "- Host preview content mentioned `2048`: `#{preview_validation.fetch("contains_2048")}`",
          "",
          host_skip_reason || "Host-side browser verification did not run.",
          "",
          "- Generated application path: `#{generated_app_dir}`",
          "- Intended host preview URL: `http://127.0.0.1:#{preview_port}/`",
          "",
          "See `review/workspace-validation.md`, `playable/host-preview.json`, `playable/host-npm-test.json`, and `playable/host-npm-build.json` for portability diagnostics.",
          "",
        ])

        return write_text(path, lines.join("\n"))
      end

      unless playwright_test&.fetch("success", false)
        lines = [
          "# Playability Verification",
          "",
          "## Host Playability Diagnostic",
          "",
          "- Host `dist/` preview reachable: `#{preview_validation.fetch("reachable")}`",
          "- Host preview content mentioned `2048`: `#{preview_validation.fetch("contains_2048")}`",
          "- Playwright verification ran: `true`",
          "- Playwright verification passed: `false`",
          "",
          "Playwright captured a real browser session and wrote `playable/host-playwright-verification.json`, but one or more acceptance assertions failed.",
          "",
          "## Observed Run Details",
          "",
          "- Merge observed: `#{playability_result["mergeObserved"]}`",
          "- Spawn observed: `#{playability_result["spawnObserved"]}`",
          "- Game over reached: `#{playability_result["gameOverReached"]}`",
          "- Restart reset score: `#{playability_result["restartResetScore"]}`",
          "- Restart reset tile count: `#{playability_result["restartResetTileCount"]}`",
          "",
          "Playwright command result excerpt:",
          "",
          "```text",
          command_result_excerpt(playwright_test, limit: 1500),
          "```",
          "",
          "See `playable/host-playwright-verification.json`, `playable/host-playability.png`, and `playable/host-playwright-test.json` for the full browser-side evidence.",
          "",
        ]

        return write_text(path, lines.join("\n"))
      end

      direction_checks = playability_result.fetch("directionChecks")
      lines = [
        "# Playability Verification",
        "",
        "Host-side browser verification was executed against:",
        "",
        "- `http://127.0.0.1:#{preview_port}/`",
        "",
        "Verification artifacts:",
        "",
        "- `playable/host-playwright-verification.json`",
        "- `playable/host-playability.png`",
        "",
        "## Verified Behaviors",
        "",
        "- Page loaded successfully from the host preview server.",
        "- Keyboard play worked with real browser input.",
      ]
      direction_checks.each_key do |key|
        lines << "- Direction produced a valid board change: `#{key}`"
      end
      lines.concat([
        "- Merge behavior was observed.",
        "- Score increased on merge.",
        "- A new tile appeared after a valid move.",
        "- A full game-over state was reached through real key presses.",
        "- Restart reset the score to `0`.",
        "- Restart reset the board to exactly two starting tiles.",
        "",
        "## Observed Run Details",
        "",
        "- Initial board had `#{playability_result.dig("initial", "nonEmpty")}` tiles.",
        "- During automated host play, score reached `#{playability_result.dig("preRestart", "score")}`.",
        "- Pre-restart state showed `#{playability_result.dig("preRestart", "status")}` with a full `4x4` board.",
        "- Post-restart state returned to `#{playability_result.dig("postRestart", "status")}` and `#{playability_result.dig("postRestart", "nonEmpty")}` starting tiles.",
        "",
        "## Host Verification Commands",
        "",
        "```bash",
        "cd #{generated_app_dir}/dist",
        "python3 -m http.server #{preview_port} --bind 127.0.0.1",
        "npm install --no-save @playwright/test@#{DEFAULT_PLAYWRIGHT_VERSION}",
        "npx playwright install chromium",
        "npx playwright test host-playability.spec.cjs --workers=1 --reporter=line",
        "```",
        "",
        "Browser validation used Playwright on the host against the platform-independent `dist/` output.",
        "",
      ])

      write_text(path, lines.join("\n"))
    end

    def command_result_excerpt(result, limit:)
      return "missing command result" if result.nil? || result.empty?

      text = [result["stderr"], result["stdout"]].compact.reject(&:empty?).join("\n").strip
      text = "no output" if text.empty?
      return text if text.length <= limit

      "#{text[0, limit]}..."
    end

    def runtime_validation_passed?(runtime_validation)
      runtime_validation.fetch("runtime_test_passed") &&
        runtime_validation.fetch("runtime_build_passed") &&
        runtime_validation.fetch("runtime_dev_server_ready") &&
        runtime_validation.fetch("runtime_browser_loaded") &&
        runtime_validation.fetch("runtime_browser_mentions_2048")
    end

    def playwright_result_available?(playwright_validation)
      playwright_validation.fetch("result", nil).present?
    end

    def playwright_verification_passed?(playwright_validation)
      playwright_result_available?(playwright_validation) &&
        playwright_validation.dig("test", "success") == true
    end

    def host_validation_passed?(host_validation:, playwright_validation:)
      host_validation.dig("npm_install", "success") &&
        host_validation.dig("npm_test", "success") &&
        host_validation.dig("npm_build", "success") &&
        host_validation.dig("preview_http", "status") == 200 &&
        playwright_verification_passed?(playwright_validation)
    end

    def build_host_preview_failure_message(error:, preview_pid:, preview_log:, preview_port:)
      process_details =
        if preview_pid
          waited_pid = Process.waitpid(preview_pid, Process::WNOHANG)
          status = $?

          if waited_pid
            if status&.exited?
              "preview process exited with status #{status.exitstatus}"
            elsif status&.signaled?
              "preview process terminated by signal #{status.termsig}"
            else
              "preview process exited unexpectedly"
            end
          else
            "preview process stayed alive but port #{preview_port} never became reachable"
          end
        else
          "preview process did not start"
        end

      log_excerpt =
        if File.exist?(preview_log)
          content = File.read(preview_log).to_s.strip
          content unless content.empty?
        end

      [
        error.message,
        process_details,
        (log_excerpt ? "preview log:\n#{log_excerpt}" : nil),
      ].compact.join("\n")
    end
    private_class_method :build_host_preview_failure_message

    def run_host_preview_and_verification!(dist_dir:, artifact_dir:, generated_app_dir:, preview_port:, attempts: 2)
      preview_log = artifact_dir.join("logs", "host-preview.log")
      last_error = nil

      attempts.times do |index|
        preview_pid = nil
        preview_out = nil

        begin
          preview_out = File.open(preview_log, index.zero? ? "w" : "a")
          preview_out.sync = true

          preview_pid = Process.spawn(
            "python3", "-m", "http.server", preview_port.to_s, "--bind", "127.0.0.1",
            chdir: dist_dir.to_s,
            out: preview_out,
            err: preview_out
          )
          wait_for_tcp_port!(host: "127.0.0.1", port: preview_port, timeout_seconds: 20)

          response, body = http_get_response("http://127.0.0.1:#{preview_port}")
          raise "host preview failed: HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

          playwright_validation = run_host_playwright_verification!(
            artifact_dir: artifact_dir,
            base_url: "http://127.0.0.1:#{preview_port}/",
            generated_app_dir: generated_app_dir
          )

          preview_http = {
            "status" => response.code.to_i,
            "contains_2048" => body.include?("2048") ||
              playwright_validation.dig("result", "initial", "nonEmpty").to_i.positive? ||
              !playwright_validation.dig("result", "initial", "status").to_s.empty?,
            "byte_size" => body.bytesize,
            "attempt_no" => index + 1,
          }

          return {
            "preview_http" => preview_http,
            "playwright_validation" => playwright_validation,
          }
        rescue => error
          last_error = build_host_preview_failure_message(
            error: error,
            preview_pid: preview_pid,
            preview_log: preview_log,
            preview_port: preview_port
          )
        ensure
          if preview_pid
            Process.kill("TERM", preview_pid) rescue nil
            Process.wait(preview_pid) rescue nil
          end
          preview_out&.close
        end

        sleep 0.5 if index + 1 < attempts
      end

      raise last_error || "host preview verification failed"
    end
    private_class_method :run_host_preview_and_verification!

    def build_playwright_script(output_json_path:, screenshot_path:)
      <<~JAVASCRIPT
        const fs = require('fs');
        const { test, expect } = require('@playwright/test');

        const baseUrl = process.env.CAPSTONE_PREVIEW_URL;
        const outputJsonPath = #{output_json_path.to_s.inspect};
        const screenshotPath = #{screenshot_path.to_s.inspect};

        function chunk(values, size) {
          const rows = [];
          for (let index = 0; index < values.length; index += size) {
            rows.push(values.slice(index, index + size));
          }
          return rows;
        }

        function sameBoard(a, b) {
          return JSON.stringify(a) === JSON.stringify(b);
        }

        async function pickFirstLocator(candidates) {
          for (const locator of candidates) {
            if ((await locator.count()) > 0) return locator.first();
          }
          throw new Error('required locator not found');
        }

        async function boardLocator(page) {
          return pickFirstLocator([
            page.getByTestId('board'),
            page.getByRole('grid', { name: /2048 board/i }),
            page.locator('[role="grid"]'),
          ]);
        }

        async function boardCellTexts(page) {
          const board = await boardLocator(page);
          let cells = board.getByRole('gridcell');
          if ((await cells.count()) === 0) {
            cells = page.locator('[data-testid^="tile-"]');
          }

          await expect(cells).toHaveCount(16);
          return (await cells.allTextContents()).map((text) => {
            const trimmed = text.trim();
            return trimmed === '' ? null : Number(trimmed);
          });
        }

        async function scoreValue(page) {
          const locator = await pickFirstLocator([
            page.getByTestId('score'),
            page.locator('[data-testid="score-value"]'),
          ]);
          const matches = (await locator.innerText()).match(/\\d+/g) || ['0'];
          return Number(matches[matches.length - 1]);
        }

        async function statusValue(page) {
          const candidates = [
            page.getByTestId('status'),
            page.getByRole('status'),
            page.locator('[aria-live]'),
          ];

          for (const locator of candidates) {
            if ((await locator.count()) > 0) {
              const text = (await locator.first().innerText()).trim();
              if (text !== '') return text;
            }
          }

          const bodyText = await page.locator('body').innerText();
          if (/game over/i.test(bodyText)) return 'Game over';
          if (/you win/i.test(bodyText)) return 'You win';

          return bodyText.trim().split(/\\n+/).find((line) => line.match(/arrow keys|wasd|restart|play/i)) || '';
        }

        async function snapshot(page) {
          const flat = await boardCellTexts(page);
          return {
            board: chunk(flat, 4),
            score: await scoreValue(page),
            status: await statusValue(page),
            nonEmpty: flat.filter((value) => value !== null && value !== 0).length,
          };
        }

        async function waitForChange(page, previous) {
          const previousJson = JSON.stringify(previous);
          try {
            await page.waitForFunction((prior) => {
              const boardElement =
                document.querySelector('[data-testid="board"]') ||
                document.querySelector('[role="grid"][aria-label*="2048 board" i]') ||
                document.querySelector('[role="grid"]');
              const cellNodes = boardElement
                ? Array.from(boardElement.querySelectorAll('[role="gridcell"]'))
                : Array.from(document.querySelectorAll('[data-testid^="tile-"]'));
              const flat = cellNodes.map((node) => {
                const text = (node.textContent || '').trim();
                return text === '' ? null : Number(text);
              });
              const rows = [];
              for (let index = 0; index < flat.length; index += 4) rows.push(flat.slice(index, index + 4));

              const scoreElement = document.querySelector('[data-testid="score"], [data-testid="score-value"]');
              const scoreText = scoreElement ? scoreElement.textContent || '' : '';
              const scoreMatches = scoreText.match(/\\d+/g) || ['0'];
              const score = Number(scoreMatches[scoreMatches.length - 1]);

              const statusElement =
                document.querySelector('[data-testid="status"]') ||
                document.querySelector('[role="status"]') ||
                document.querySelector('[aria-live]');
              const status = (statusElement ? statusElement.textContent : document.body.textContent || '').trim();

              return JSON.stringify({
                board: rows,
                score,
                status,
                nonEmpty: flat.filter((value) => value !== null && value !== 0).length,
              }) !== prior;
            }, previousJson, { timeout: 500 });
            return true;
          } catch (_error) {
            return false;
          }
        }

        async function restartLocator(page) {
          return pickFirstLocator([
            page.getByTestId('restart'),
            page.getByRole('button', { name: /restart|new game|play again/i }),
          ]);
        }

        async function waitForFreshBoard(page) {
          await page.waitForFunction(() => {
            const scoreElement = document.querySelector('[data-testid="score"], [data-testid="score-value"]');
            const scoreText = scoreElement ? scoreElement.textContent || '' : '';
            const scoreMatches = scoreText.match(/\\d+/g) || ['0'];
            const score = Number(scoreMatches[scoreMatches.length - 1]);

            const boardElement =
              document.querySelector('[data-testid="board"]') ||
              document.querySelector('[role="grid"][aria-label*="2048 board" i]') ||
              document.querySelector('[role="grid"]');
            const cellNodes = boardElement
              ? Array.from(boardElement.querySelectorAll('[role="gridcell"]'))
              : Array.from(document.querySelectorAll('[data-testid^="tile-"]'));
            const nonEmpty = cellNodes.filter((node) => {
              const text = (node.textContent || '').trim();
              return text !== '' && text !== '0';
            }).length;

            return score === 0 && nonEmpty === 2;
          }, { timeout: 3000 });
        }

        async function restartGame(page) {
          const restart = await restartLocator(page);
          await restart.click();
          await waitForFreshBoard(page);
          return snapshot(page);
        }

        async function verifyDirectionFromFreshBoard(page, key, maxAttempts = 20) {
          for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
            const before = attempt === 0 ? await snapshot(page) : await restartGame(page);
            await page.keyboard.press(key);
            const changed = await waitForChange(page, before);
            if (!changed) continue;

            const after = await snapshot(page);
            return {
              changed: true,
              beforeScore: before.score,
              afterScore: after.score,
              attempts: attempt + 1,
            };
          }

          return {
            changed: false,
            beforeScore: null,
            afterScore: null,
            attempts: maxAttempts,
          };
        }

        test('host-side 2048 playability', async ({ page }) => {
          test.setTimeout(180000);
          const gameOverStatusPattern = /game(?:\\s|-)?over/i;

          await page.goto(baseUrl, { waitUntil: 'networkidle' });
          await expect(await boardLocator(page)).toBeVisible();

          const directionChecks = {};
          for (const key of ['ArrowLeft', 'ArrowUp', 'ArrowRight', 'ArrowDown']) {
            directionChecks[key] = await verifyDirectionFromFreshBoard(page, key);
          }

          await restartGame(page);

          let mergeObserved = false;
          let spawnObserved = false;
          let current = await snapshot(page);
          const initial = current;
          const priority = ['ArrowUp', 'ArrowLeft', 'ArrowRight', 'ArrowDown'];

          for (let step = 0; step < 1500; step += 1) {
            if (gameOverStatusPattern.test(current.status)) break;

            let moved = false;
            for (const key of priority) {
              const before = current;
              await page.keyboard.press(key);
              const changed = await waitForChange(page, before);
              if (!changed) continue;

              const after = await snapshot(page);
              directionChecks[key] = {
                changed: true,
                beforeScore: before.score,
                afterScore: after.score,
              };
              if (after.score > before.score) mergeObserved = true;
              if (after.score === before.score && after.nonEmpty > before.nonEmpty) spawnObserved = true;

              current = after;
              moved = true;
              break;
            }

            if (!moved) {
              await page.keyboard.press('ArrowUp');
              current = await snapshot(page);
              if (gameOverStatusPattern.test(current.status)) break;
              if (current.nonEmpty === 16) break;
            }
          }

          if (!gameOverStatusPattern.test(current.status)) {
            for (let attempt = 0; attempt < 20; attempt += 1) {
              await page.keyboard.press('ArrowUp');
              await page.keyboard.press('ArrowLeft');
              current = await snapshot(page);
              if (gameOverStatusPattern.test(current.status)) break;
            }
          }

          const preRestart = current;
          const postRestart = await restartGame(page);
          await page.screenshot({ path: screenshotPath, fullPage: true });

          const result = {
            initial,
            directionChecks,
            mergeObserved,
            spawnObserved,
            gameOverReached: gameOverStatusPattern.test(preRestart.status),
            preRestart,
            postRestart,
            restartResetScore: postRestart.score === 0,
            restartResetTileCount: postRestart.nonEmpty === 2,
            screenshotPath,
          };

          fs.writeFileSync(outputJsonPath, JSON.stringify(result, null, 2));

          expect(result.mergeObserved).toBe(true);
          expect(result.spawnObserved).toBe(true);
          expect(result.gameOverReached).toBe(true);
          expect(result.restartResetScore).toBe(true);
          expect(result.restartResetTileCount).toBe(true);
          expect(Object.values(result.directionChecks).every((entry) => entry.changed)).toBe(true);
        });
      JAVASCRIPT
    end
    private_class_method :build_playwright_script

    def run_host_playwright_verification!(artifact_dir:, base_url:, generated_app_dir:)
      artifact_spec_path = artifact_dir.join("tmp", "host-playability.spec.cjs")
      runner_spec_path = generated_app_dir.join("host-playability.spec.cjs")
      output_json_path = artifact_dir.join("playable", "host-playwright-verification.json")
      screenshot_path = artifact_dir.join("playable", "host-playability.png")
      script = build_playwright_script(output_json_path:, screenshot_path:)

      write_text(artifact_spec_path, script)
      write_text(runner_spec_path, script)

      dependency_install = nil
      browser_install = nil
      test_result = nil

      begin
        dependency_install = capture_command!(
          "npm", "install", "--no-save", "@playwright/test@#{DEFAULT_PLAYWRIGHT_VERSION}",
          chdir: generated_app_dir,
          failure_label: "install Playwright host test dependency"
        )
        browser_install = capture_command!(
          "npx", "playwright", "install", "chromium",
          chdir: generated_app_dir,
          failure_label: "install Playwright chromium"
        )
        test_result = capture_command(
          "npx", "playwright", "test", runner_spec_path.basename.to_s, "--workers=1", "--reporter=line",
          chdir: generated_app_dir,
          env: { "CAPSTONE_PREVIEW_URL" => base_url },
        )
        result = JSON.parse(File.read(output_json_path)) if File.exist?(output_json_path)

        if !test_result.fetch("success") && result.blank?
          details = test_result.fetch("stderr").presence || test_result.fetch("stdout").presence || "no output"
          raise "run Playwright host verification failed:\n#{details}"
        end

        {
          "install" => {
            "dependency_install" => dependency_install,
            "browser_install" => browser_install,
          },
          "test" => test_result,
          "result" => result,
          "output_json_path" => output_json_path.to_s,
          "screenshot_path" => screenshot_path.to_s,
          "spec_path" => artifact_spec_path.to_s,
        }
      ensure
        FileUtils.rm_f(runner_spec_path)
      end
    end
    private_class_method :run_host_playwright_verification!

    def http_get_response(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, read_timeout: 30, open_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        [response, response.body.to_s]
      end
    end
    private_class_method :http_get_response

    def capture_command(*command, chdir:, env: {})
      stdout, stderr, status = Open3.capture3(env, *command, chdir: chdir.to_s)
      {
        "command" => command.join(" "),
        "cwd" => chdir.to_s,
        "success" => status.success?,
        "exit_status" => status.exitstatus,
        "stdout" => stdout,
        "stderr" => stderr,
      }
    end
    private_class_method :capture_command

    def capture_command!(*command, chdir:, env: {}, failure_label: nil)
      result = capture_command(*command, chdir: chdir, env: env)
      return result if result.fetch("success")

      label = failure_label || command.join(" ")
      details = result.fetch("stderr").to_s
      details = result.fetch("stdout").to_s if details.empty?
      details = "no output" if details.empty?
      raise "#{label} failed:\n#{details}"
    end
    private_class_method :capture_command!

    def wait_for_tcp_port!(host:, port:, timeout_seconds:)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        begin
          socket = TCPSocket.new(host, port)
          socket.close
          return
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

          sleep(0.2)
        end
      end
    end
    private_class_method :wait_for_tcp_port!

    def write_json(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload) + "\n")
    end
    private_class_method :write_json

    def write_text(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, contents)
    end
    private_class_method :write_text
  end
end
