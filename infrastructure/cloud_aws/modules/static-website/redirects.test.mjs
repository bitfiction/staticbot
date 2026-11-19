/**
 * Tests for the viewer_request CloudFront Function in redirects.tf: the www redirect keeps the query.
 *
 * Run: node --test infrastructure/cloud_aws/modules/static-website/redirects.test.mjs
 *
 * The events below use the shape CloudFront really sends, checked 2026-11-19 on a probe
 * distribution: names and values arrive exactly as the viewer sent them (still percent-encoded),
 * a repeated name carries `multiValue`, and a bare "?flag" arrives as { value: "" }.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const TF = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "redirects.tf"), "utf8");

/** The viewer_request handler as Terraform renders it, with its variables substituted. */
async function handler({ wwwRedirect = true, domain = "example.com" } = {}) {
  const block = TF.slice(TF.indexOf('resource "aws_cloudfront_function" "viewer_request"'));
  const code = block.match(/code = <<-EOF\n([\s\S]*?)\nEOF\n/)[1];
  const rendered = code
    .replace("${var.maintenance_mode}", "false")
    .replace("${jsonencode(var.maintenance_allowed_ips)}", "[]")
    .replace("${jsonencode(var.redirects)}", "[]")
    .replace("${var.www_redirect}", String(wwwRedirect))
    .replace("${var.domain_name}", domain)
    .replace("${local.functions_proxy_enabled}", "true");
  assert.ok(!rendered.includes("${"), "every Terraform interpolation must be substituted");
  const src = rendered + "\nexport { handler };\n";
  return (await import("data:text/javascript;base64," + Buffer.from(src).toString("base64"))).handler;
}

const request = (host, uri, querystring = {}) => ({
  viewer: { ip: "198.51.100.11" },
  request: { uri, querystring, headers: { host: { value: host } } },
});
const location = async (host, uri, querystring) =>
  (await handler())(request(host, uri, querystring)).headers.location.value;

test("the apex redirect keeps a PKCE code and an encoded state byte for byte", async () => {
  assert.equal(
    await location("example.com", "/auth/callback", { code: { value: "abc123" }, state: { value: "x%2Fy" } }),
    "https://www.example.com/auth/callback?code=abc123&state=x%2Fy",
  );
});

test("already-encoded values are not encoded again", async () => {
  const qs = {
    q: { value: "foo+bar" },
    email: { value: "user%2Btag%40ex.com" },
    amp: { value: "a%26b" },
    pct: { value: "100%25" },
  };
  assert.equal(
    await location("example.com", "/s", qs),
    "https://www.example.com/s?q=foo+bar&email=user%2Btag%40ex.com&amp=a%26b&pct=100%25",
  );
});

test("repeated names keep their order and a bare flag becomes flag=", async () => {
  const qs = { flag: { value: "" }, a: { value: "1", multiValue: [{ value: "1" }, { value: "2" }] } };
  assert.equal(await location("example.com", "/p", qs), "https://www.example.com/p?flag=&a=1&a=2");
});

test("characters a Location header cannot carry are percent-encoded", async () => {
  assert.equal(
    await location("example.com", "/p", { raw: { value: "é" }, sp: { value: "a b" } }),
    "https://www.example.com/p?raw=%C3%A9&sp=a%20b",
  );
});

test("no query means no question mark", async () => {
  assert.equal(await location("example.com", "/reset-password"), "https://www.example.com/reset-password");
});

test("a value encodeURIComponent rejects redirects without the query instead of failing the request", async () => {
  assert.equal(await location("example.com", "/p", { bad: { value: "\uD800" } }), "https://www.example.com/p");
});

test("www requests and sites without the www redirect are not redirected", async () => {
  const onWww = (await handler())(request("www.example.com", "/about", { a: { value: "1" } }));
  assert.equal(onWww.statusCode, undefined);
  const noRedirect = (await handler({ wwwRedirect: false }))(request("example.com", "/about", { a: { value: "1" } }));
  assert.equal(noRedirect.statusCode, undefined);
});
