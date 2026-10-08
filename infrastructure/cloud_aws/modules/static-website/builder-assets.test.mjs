/**
 * Tests for the two CloudFront Functions in builder-assets.tf — the production static site's
 * "/__l5e/*" path.
 *
 * Their source lives inside Terraform heredocs, so it is extracted from the .tf and evaluated here.
 * That is deliberate rather than moving them to files: keeping the code beside the
 * `function_association` that attaches it is what makes the blast-radius argument legible, and the
 * extraction is five lines.
 *
 * The response handler only sets the immutable cache header. It used to also rewrite a
 * 200-with-the-SPA-shell back into a 404; that branch was removed on 2026-09-20 after prod showed
 * Supabase answers a miss with HTTP 400 (so `custom_error_response` — which covers 403/404/500 —
 * never fires on this path), and AWS documents that a CloudFront Function does not run at all when
 * the origin returns >=400. See builder-assets.tf for the full reasoning.
 *
 * Run: node --test infrastructure/cloud_aws/modules/static-website/builder-assets.test.mjs
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const TF = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "builder-assets.tf"),
  "utf8",
);

/** Every `code = <<-JS … JS` heredoc in the file, in declaration order. */
function extractHandlers() {
  const blocks = [...TF.matchAll(/code = <<-JS\n([\s\S]*?)\n\s*JS\n/g)].map((m) => m[1]);
  assert.equal(blocks.length, 2, "expected exactly the request and response handlers");
  return blocks;
}

async function loadHandler(index) {
  const src = extractHandlers()[index] + "\nexport { handler };\n";
  const mod = await import("data:text/javascript;base64," + Buffer.from(src).toString("base64"));
  return mod.handler;
}

const requestHandler = () => loadHandler(0);
const responseHandler = () => loadHandler(1);

const req = (uri) => ({ request: { uri } });
const res = (statusCode, contentType, cacheControl) => ({
  response: {
    statusCode,
    statusDescription: "OK",
    headers: {
      ...(contentType ? { "content-type": { value: contentType } } : {}),
      ...(cacheControl ? { "cache-control": { value: cacheControl } } : {}),
    },
  },
});

// ── viewer-request: strip the marker so origin_path supplies the storage path ──

test("strips /__l5e so origin_path can supply the Supabase storage prefix", async () => {
  const handler = await requestHandler();

  const out = handler(req("/__l5e/assets-v1/0f2c-6939/hero.jpg"));

  assert.equal(out.uri, "/assets-v1/0f2c-6939/hero.jpg");
});

test("a traversal never reaches the origin", async () => {
  const handler = await requestHandler();

  assert.equal(handler(req("/__l5e/../../etc/passwd")).statusCode, 404);
});

test("a bare /__l5e/ with no key is refused", async () => {
  const handler = await requestHandler();

  assert.equal(handler(req("/__l5e/")).statusCode, 404);
});

test("a non-asset path is refused rather than rewritten", async () => {
  // Defence in depth: the function is attached only to the "/__l5e/*" behaviour, and it must never
  // start mangling ordinary page requests if that ever changes.
  const handler = await requestHandler();

  assert.equal(handler(req("/dashboard")).statusCode, 404);
});

// ── viewer-response: undo the distribution-wide 404 -> index.html/200 rule ──

test("a miss never reaches this handler, but if one did it would not be cached", async () => {
  // Defence in depth only. A real miss is an origin 400 and CloudFront skips the function entirely;
  // this asserts the handler would still not stamp a year-long cache header on a non-200.
  const handler = await responseHandler();

  const out = handler(res(400, "application/json", "no-store"));

  assert.equal(out.statusCode, 400);
  assert.equal(out.headers["cache-control"].value, "no-store", "left exactly as the origin sent it");
});

test("a real asset is cached immutably", async () => {
  // The asset id in the path changes whenever the bytes do, so Supabase's own max-age=3600 is
  // needlessly conservative — and every revalidation is egress on the customer's bill.
  const handler = await responseHandler();

  const out = handler(res(200, "image/jpeg", "public, max-age=3600"));

  assert.equal(out.statusCode, 200);
  assert.equal(out.headers["cache-control"].value, "public, max-age=31536000, immutable");
});

test("a 304 keeps the immutable header too", async () => {
  const handler = await responseHandler();

  assert.equal(
    handler(res(304, "image/jpeg")).headers["cache-control"].value,
    "public, max-age=31536000, immutable",
  );
});

test("a genuine origin error is left exactly as it is", async () => {
  const handler = await responseHandler();

  const out = handler(res(503, "text/plain"));

  assert.equal(out.statusCode, 503);
  assert.equal(out.headers["cache-control"], undefined);
});

test("a response with no content-type at all does not crash", async () => {
  const handler = await responseHandler();

  assert.equal(handler(res(200, null)).statusCode, 200);
});
