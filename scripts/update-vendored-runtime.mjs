#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const packages = [
  { name: "@earendil-works/pi-ai", directory: "packages/ai" },
  { name: "@earendil-works/pi-tui", directory: "packages/tui" },
  { name: "@earendil-works/pi-agent-core", directory: "packages/agent" },
  { name: "@earendil-works/pi-coding-agent", directory: "packages/coding-agent" },
];

const options = parseArgs(process.argv.slice(2));
const platform = options.platform ?? "darwin-arm64";
if (platform !== "darwin-arm64") {
  throw new Error(`Only darwin-arm64 is configured for now, got ${platform}`);
}

const piRepoOption = options.piRepo ?? process.env.AGENTMAC_PI_REPO_PATH;
if (!piRepoOption) {
  throw new Error("Pi repo path is required. Pass --pi-repo or set AGENTMAC_PI_REPO_PATH.");
}

const piRepo = resolve(piRepoOption);
const nodePath = realpathSync(resolve(options.nodePath ?? process.execPath));
const buildRoot = join(repoRoot, ".build-runtime");
const packDir = join(buildRoot, "pi-packs");
const installDir = join(buildRoot, "pi-install");
const vendorRoot = join(repoRoot, "Vendor", "Runtime", platform);

if (!existsSync(join(piRepo, "package.json"))) {
  throw new Error(`Pi repo package.json not found: ${piRepo}`);
}

if (!options.skipNpmCi) {
  run("npm", ["ci", "--ignore-scripts"], { cwd: piRepo });
}
if (!options.skipPiBuild) {
  run("npm", ["run", "build"], { cwd: piRepo });
}

rmSync(packDir, { force: true, recursive: true });
rmSync(installDir, { force: true, recursive: true });
mkdirSync(packDir, { recursive: true });
mkdirSync(installDir, { recursive: true });

const dependencies = {};
for (const pkg of packages) {
  const output = run(
    "npm",
    ["pack", "--json", "--pack-destination", packDir],
    { cwd: join(piRepo, pkg.directory), capture: true },
  );
  const packed = JSON.parse(output)[0];
  dependencies[pkg.name] = `file:${relative(installDir, join(packDir, packed.filename)).replaceAll("\\", "/")}`;
}

writeFileSync(
  join(installDir, "package.json"),
  `${JSON.stringify({ private: true, type: "module", dependencies }, null, 2)}\n`,
);
run("npm", ["install", "--ignore-scripts", "--omit=dev", "--no-audit", "--no-fund"], { cwd: installDir });

rmSync(vendorRoot, { force: true, recursive: true });
mkdirSync(join(vendorRoot, "node", "bin"), { recursive: true });
mkdirSync(join(vendorRoot, "pi"), { recursive: true });

const vendorNodePath = join(vendorRoot, "node", "bin", "node");
cpSync(nodePath, vendorNodePath);
chmodSync(vendorNodePath, 0o755);
stripAndSignNode(vendorNodePath);
cpSync(join(installDir, "node_modules"), join(vendorRoot, "pi", "node_modules"), { recursive: true });

const manifest = {
  platform,
  node: {
    version: process.version,
    arch: process.arch,
    platform: process.platform,
  },
  pi: {
    packageVersion: readJson(join(piRepo, "packages", "coding-agent", "package.json")).version,
    package: "@earendil-works/pi-coding-agent",
  },
  generatedAt: new Date().toISOString(),
};
writeFileSync(join(vendorRoot, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
run("xattr", ["-cr", vendorRoot], { cwd: repoRoot });

console.log(`Updated ${relative(repoRoot, vendorRoot)}`);

function parseArgs(args) {
  const parsed = {
    piRepo: undefined,
    nodePath: undefined,
    platform: undefined,
    skipNpmCi: false,
    skipPiBuild: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--pi-repo") {
      parsed.piRepo = args[++index];
    } else if (arg === "--node") {
      parsed.nodePath = args[++index];
    } else if (arg === "--platform") {
      parsed.platform = args[++index];
    } else if (arg === "--skip-npm-ci") {
      parsed.skipNpmCi = true;
    } else if (arg === "--skip-pi-build") {
      parsed.skipPiBuild = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function run(command, args, { cwd, capture = false }) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: capture ? ["ignore", "pipe", "inherit"] : "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${[command, ...args].join(" ")}`);
  }
  return result.stdout ?? "";
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function stripAndSignNode(path) {
  run("/usr/bin/strip", ["-S", path], { cwd: repoRoot });
  run("/usr/bin/strip", ["-x", path], { cwd: repoRoot });
  run("/usr/bin/codesign", ["--force", "--sign", "-", path], { cwd: repoRoot });
  run("xattr", ["-cr", path], { cwd: repoRoot });
}
