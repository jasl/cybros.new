#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import process from "node:process";
import { createInterface } from "node:readline";
import { chromium } from "playwright";

let browser = null;
let page = null;

function configuredExecutablePath() {
  return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || findChromiumExecutablePath();
}

function findChromiumExecutablePath() {
  try {
    const output = execFileSync(
      "/bin/sh",
      [
        "-lc",
        "command -v chromium || command -v chromium-browser || command -v google-chrome || command -v google-chrome-stable"
      ],
      { encoding: "utf8" }
    ).trim();

    return output || undefined;
  } catch {
    return undefined;
  }
}

async function ensurePage() {
  if (page) return page;

  const configuration = {
    headless: true,
  };
  const executablePath = configuredExecutablePath();
  if (executablePath) {
    configuration.executablePath = executablePath;
  }

  try {
    browser = await chromium.launch(configuration);
  } catch (error) {
    if (!executablePath) {
      throw new Error(
        `could not launch Playwright Chromium; install Chromium on the host, run 'pnpm exec playwright install chromium', or set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH (${error.message})`
      );
    }

    throw error;
  }

  page = await browser.newPage();
  return page;
}

async function dispatch(command, argumentsPayload) {
  switch (command) {
    case "open": {
      const activePage = await ensurePage();
      if (argumentsPayload.url) {
        await activePage.goto(argumentsPayload.url, { waitUntil: "networkidle" });
      }
      return { current_url: activePage.url() };
    }
    case "navigate": {
      const activePage = await ensurePage();
      await activePage.goto(argumentsPayload.url, { waitUntil: "networkidle" });
      return { current_url: activePage.url() };
    }
    case "get_content": {
      const activePage = await ensurePage();
      const content = await activePage.locator("body").innerText().catch(async () => activePage.content());
      return { current_url: activePage.url(), content };
    }
    case "screenshot": {
      const activePage = await ensurePage();
      const image = await activePage.screenshot({
        fullPage: argumentsPayload.full_page !== false,
        type: "png",
      });

      return {
        current_url: activePage.url(),
        mime_type: "image/png",
        image_base64: image.toString("base64"),
      };
    }
    case "close": {
      if (browser) {
        await browser.close();
      }
      browser = null;
      page = null;
      return { closed: true };
    }
    default:
      throw new Error(`unsupported browser host command ${command}`);
  }
}

async function closeBrowser() {
  if (!browser) return;

  await browser.close().catch(() => undefined);
  browser = null;
  page = null;
}

const readline = createInterface({ input: process.stdin, crlfDelay: Infinity });

process.on("SIGINT", async () => {
  await closeBrowser();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  await closeBrowser();
  process.exit(0);
});

readline.on("close", async () => {
  await closeBrowser();
  process.exit(0);
});

readline.on("line", async line => {
  try {
    const payload = JSON.parse(line);
    const responsePayload = await dispatch(payload.command, payload.arguments || {});
    process.stdout.write(`${JSON.stringify({ payload: responsePayload })}\n`);

    if (payload.command === "close") {
      process.exit(0);
    }
  } catch (error) {
    process.stdout.write(`${JSON.stringify({ error: error.message })}\n`);
  }
});
