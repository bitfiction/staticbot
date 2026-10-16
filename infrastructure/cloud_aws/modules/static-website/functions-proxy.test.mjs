/**
 * Tests for the CloudFront Function in functions-proxy.tf: "/functions/<path>" on a live Base44 site
 * is proxied to the customer's Supabase at origin_path "/functions/v1" + "/<path>".
 *
 * Run: node --test infrastructure/cloud_aws/modules/static-website/functions-proxy.test.mjs
 * (The distribution wiring is covered by `tofu test` in this module.)
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const TF = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "functions-proxy.tf"), "utf8");

/** The handler as Terraform renders it, with the maintenance variables substituted. */
async function handler({ maintenance = false, allowed = [] } = {}) {
  const blocks = [...TF.matchAll(/code = <<-JS\n([\s\S]*?)\n\s*JS\n/g)].map((m) => m[1]);
  assert.equal(blocks.length, 1, "expected exactly one handler");
  const rendered = blocks[0]
    .replace("${var.maintenance_mode}", String(maintenance))
    .replace("${jsonencode(var.maintenance_allowed_ips)}", JSON.stringify(allowed));
  assert.ok(!rendered.includes("${"), "every Terraform interpolation must be substituted");
  const src = rendered + "\nexport { handler };\n";
  return (await import("data:text/javascript;base64," + Buffer.from(src).toString("base64"))).handler;
}

const run = async (uri, opts = {}, ip = "198.51.100.11") =>
  (await handler(opts))({ viewer: { ip }, request: { uri, method: "POST" } });

test("a top-level Base44 function keeps its URL", async () => {
  assert.equal((await run("/functions/whopWebhook")).uri, "/whopWebhook");
});

test("a nested endpoint reaches its folder's router", async () => {
  // origin_path /functions/v1 + /v1/chat/completions = the v1 router, which sees /v1/chat/completions
  assert.equal((await run("/functions/v1/chat/completions")).uri, "/v1/chat/completions");
});

test("a bare /functions/ or a traversal is a JSON 404, never the origin", async () => {
  for (const uri of ["/functions/", "/functions/../x", "/other"]) {
    const res = await run(uri);
    assert.equal(res.statusCode, 404, uri);
    assert.equal(res.headers["content-type"].value, "application/json");
  }
});

test("maintenance mode answers function calls with 503 JSON instead of running them", async () => {
  const res = await run("/functions/updateProfile", { maintenance: true });
  assert.equal(res.statusCode, 503);
  assert.equal(res.headers["content-type"].value, "application/json");
});

test("an allowed IP still reaches functions during maintenance", async () => {
  const res = await run("/functions/updateProfile", { maintenance: true, allowed: ["198.51.100.11"] });
  assert.equal(res.uri, "/updateProfile");
});
