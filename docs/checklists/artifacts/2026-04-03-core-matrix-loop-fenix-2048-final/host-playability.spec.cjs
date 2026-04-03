const fs = require('fs');
const { test, expect } = require('@playwright/test');

const baseUrl = process.env.CAPSTONE_PREVIEW_URL;
const outputJsonPath = "/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/artifacts/2026-04-03-core-matrix-loop-fenix-2048-final/host-playwright-verification.json";
const screenshotPath = "/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/artifacts/2026-04-03-core-matrix-loop-fenix-2048-final/host-playability.png";

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
  const matches = (await locator.innerText()).match(/\d+/g) || ['0'];
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

  return bodyText.trim().split(/\n+/).find((line) => line.match(/arrow keys|wasd|restart|play/i)) || '';
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
      const scoreMatches = scoreText.match(/\d+/g) || ['0'];
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
    const scoreMatches = scoreText.match(/\d+/g) || ['0'];
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
  const gameOverStatusPattern = /game(?: |-)?over/i;

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
