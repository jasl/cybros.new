#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";

let browser = null;
let page = null;
let playwrightModulePromise = null;

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

  const { chromium } = await resolvePlaywrightModule();
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
        `could not launch Playwright Chromium; install the global Playwright package, run 'playwright install chromium', install Chromium on the host, or set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH (${error.message})`
      );
    }

    throw error;
  }

  page = await browser.newPage();
  return page;
}

async function resolvePlaywrightModule() {
  playwrightModulePromise ||= loadPlaywrightModule();
  return playwrightModulePromise;
}

async function loadPlaywrightModule() {
  try {
    return await import("playwright");
  } catch (localError) {
    if (!playwrightModuleMissing(localError)) {
      throw localError;
    }

    const globalModuleUrl = globalPlaywrightModuleUrl();

    if (globalModuleUrl) {
      try {
        return await import(globalModuleUrl);
      } catch (globalError) {
        throw new Error(
          `could not load Playwright from the global npm root (${globalError.message}); install it globally with 'npm install -g playwright'`
        );
      }
    }

    throw new Error(
      `could not load Playwright (${localError.message}); install it globally with 'npm install -g playwright'`
    );
  }
}

function playwrightModuleMissing(error) {
  return error?.code === "ERR_MODULE_NOT_FOUND" &&
    error.message.includes("Cannot find package 'playwright'");
}

function globalPlaywrightModuleUrl() {
  const packageJsonPath = resolveGlobalPackageJsonPath("playwright");
  if (!packageJsonPath) return null;

  const importEntry = packageImportEntry(packageJsonPath);
  if (!importEntry) return null;

  const modulePath = path.resolve(path.dirname(packageJsonPath), importEntry);
  if (!fs.existsSync(modulePath)) return null;

  return pathToFileURL(modulePath).href;
}

function resolveGlobalPackageJsonPath(packageName) {
  const globalNodeModulesRoot = globalNodeModulesPath();
  if (!globalNodeModulesRoot) return null;

  const packageJsonPath = path.join(globalNodeModulesRoot, packageName, "package.json");
  return fs.existsSync(packageJsonPath) ? packageJsonPath : null;
}

function packageImportEntry(packageJsonPath) {
  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    const exportsRoot = packageJson.exports?.["."];

    if (typeof exportsRoot === "string") return exportsRoot;
    if (typeof exportsRoot?.import === "string") return exportsRoot.import;
    if (typeof packageJson.module === "string") return packageJson.module;
    if (typeof packageJson.main === "string") return packageJson.main;
  } catch {
    return null;
  }

  return null;
}

function globalNodeModulesPath() {
  try {
    return execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim() || null;
  } catch {
    return null;
  }
}

async function dispatch(command, argumentsPayload) {
  switch (command) {
    case "probe": {
      try {
        const { chromium } = await resolvePlaywrightModule();
        const explicitExecutablePath = configuredExecutablePath();
        const executablePath = explicitExecutablePath || chromium.executablePath?.() || null;
        const available = Boolean(executablePath && fs.existsSync(executablePath));
        const missingExecutableMessage = explicitExecutablePath
          ? `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH does not point to an executable browser (${explicitExecutablePath})`
          : "install Chromium on the host, run 'playwright install chromium', or set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH";

        return {
          available,
          executable_path: executablePath,
          module_available: true,
          reason: available ? null : "browser_executable_missing",
          message: available ? null : missingExecutableMessage,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);

        return {
          available: false,
          executable_path: null,
          module_available: false,
          reason: /could not load Playwright/i.test(message) ? "playwright_missing" : "probe_failed",
          message,
        };
      }
    }
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
