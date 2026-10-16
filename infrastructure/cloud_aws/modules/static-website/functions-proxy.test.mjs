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

async function handler() {
  const blocks = [...TF.matchAll(/code = <<-JS\n([\s\S]*?)\n\s*JS\n/g)].map((m) => m[1]);
  assert.equal(blocks.length, 1, "expected exactly one handler");
  const src = blocks[0] + "\nexport { handler };\n";
  return (await import("data:text/javascript;base64," + Buffer.from(src).toString("base64"))).handler;
}

const run = async (uri) => (await handler())({ request: { uri, method: "POST" } });

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
