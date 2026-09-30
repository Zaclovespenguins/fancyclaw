#!/usr/bin/env node
// Regenerates Packages/FancyClawKit/Sources/TestSupport/Fixtures/protocol.schema.json from the published
// @openclaw/gateway-protocol package.
//
// The full schema is ~4 MB and covers hundreds of methods, so only the definitions FancyClaw models are
// kept. Add a name to DEFINITIONS when a new protocol model starts being validated against the schema.
//
// Usage: node Scripts/refresh-protocol-schema.mjs [version]   (defaults to the pinned release)

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PINNED_RELEASE = "2026.9.6"; // Keep in sync with ProtocolVersion.pinnedRelease.
const PACKAGE = "@openclaw/gateway-protocol";
const DEFINITIONS = [
  "RequestFrame",
  "ResponseFrame",
  "EventFrame",
  "ErrorShape",
  "MissingScopeErrorDetails",
  "ConnectParams",
  "HelloOk",
  "TickEvent",
  "ShutdownEvent",
  "ChatEvent",
  "ChatSendParams",
  "ChatAbortParams",
  "ChatHistoryParams",
  "ChatHistoryCursorResult",
  "SessionsListParams",
  "SessionRow",
  "SessionsCreateParams",
  "SessionsPatchParams",
  "SessionsResetParams",
  "SessionsDeleteParams",
  "ModelsListParams",
  "ExecApprovalResolveParams",
];

const release = process.argv[2] ?? PINNED_RELEASE;
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const output = join(repoRoot, "Packages/FancyClawKit/Sources/TestSupport/Fixtures/protocol.schema.json");
const workDir = mkdtempSync(join(tmpdir(), "fancyclaw-protocol-"));

try {
  const packOutput = execFileSync("npm", ["pack", `${PACKAGE}@${release}`, "--json", "--pack-destination", workDir], {
    encoding: "utf8",
  });
  const [{ filename, integrity }] = JSON.parse(packOutput);
  execFileSync("tar", ["xzf", join(workDir, filename), "-C", workDir]);

  const schema = JSON.parse(readFileSync(join(workDir, "package/protocol.schema.json"), "utf8"));
  const missing = DEFINITIONS.filter((name) => !(name in schema.definitions));
  if (missing.length > 0) {
    throw new Error(`Definitions missing from ${PACKAGE}@${release}: ${missing.join(", ")}`);
  }
  if (JSON.stringify(schema.definitions).includes('"$ref"')) {
    throw new Error("The schema now uses $ref; teach TestSupport/ProtocolSchema.swift to resolve references.");
  }

  const subset = {
    $schema: schema.$schema,
    $id: schema.$id,
    title: `${schema.title} (FancyClaw subset)`,
    "x-fancyclaw": { package: PACKAGE, release, integrity, generatedBy: "Scripts/refresh-protocol-schema.mjs" },
    definitions: Object.fromEntries(DEFINITIONS.map((name) => [name, schema.definitions[name]])),
  };
  writeFileSync(output, `${JSON.stringify(subset, null, 2)}\n`);
  console.log(`Wrote ${DEFINITIONS.length} definitions from ${PACKAGE}@${release} to ${output}`);
} finally {
  rmSync(workDir, { recursive: true, force: true });
}
