#!/usr/bin/env node
"use strict";

const { spawnSync } = require("child_process");
const path = require("path");

function runCommand(command, args) {
  const result = spawnSync(command, args, {
    stdio: "pipe",
    encoding: "utf8"
  });

  if (result.error) {
    return { executed: false, ok: false, error: result.error.message };
  }

  return {
    executed: true,
    ok: result.status === 0,
    stderr: typeof result.stderr === "string" ? result.stderr.trim() : ""
  };
}

function resolveFilePath(toolInput) {
  const candidate =
    toolInput.file_path ||
    toolInput.filePath ||
    toolInput.path ||
    "";

  if (!candidate) {
    return "";
  }

  return path.isAbsolute(candidate)
    ? candidate
    : path.resolve(process.cwd(), candidate);
}

function selectFormatterCandidates(filePath) {
  const ext = path.extname(filePath).toLowerCase();

  if (ext === ".py") {
    return [
      ["ruff", ["format", filePath]],
      ["python", ["-m", "ruff", "format", filePath]],
      ["python", ["-m", "black", "--quiet", filePath]]
    ];
  }

  if (ext === ".sh" || ext === ".bash") {
    return [["shfmt", ["-w", filePath]]];
  }

  if (ext === ".tf" || ext === ".tfvars") {
    return [["terraform", ["fmt", filePath]]];
  }

  if (
    ext === ".js" ||
    ext === ".ts" ||
    ext === ".json" ||
    ext === ".md" ||
    ext === ".yaml" ||
    ext === ".yml"
  ) {
    return [["npx", ["--no-install", "prettier", "--write", filePath]]];
  }

  return [];
}

function shouldFormat(input) {
  const toolName = (input.tool_name || "").toLowerCase();
  return toolName === "edit" || toolName === "write";
}

let rawInput = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  rawInput += chunk;
});

process.stdin.on("end", () => {
  try {
    const input = JSON.parse(rawInput || "{}");

    if (!shouldFormat(input)) {
      process.stdout.write(rawInput);
      return;
    }

    const toolInput = input.tool_input || {};
    const filePath = resolveFilePath(toolInput);

    if (!filePath) {
      process.stdout.write(rawInput);
      return;
    }

    const candidates = selectFormatterCandidates(filePath);
    if (candidates.length === 0) {
      process.stdout.write(rawInput);
      return;
    }

    for (const [command, args] of candidates) {
      const result = runCommand(command, args);
      if (!result.executed) {
        continue;
      }
      if (result.ok) {
        process.stdout.write(rawInput);
        return;
      }
    }
  } catch {
    // Ignore parser and formatter errors to keep hooks non-blocking.
  }

  process.stdout.write(rawInput);
});

process.stdin.resume();
