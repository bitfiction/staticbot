# Builder CDN assets on a customer's LIVE static site.
#
# "Production" in the surrounding docs means this: one CloudFront distribution per customer site,
# built by this module from an INFRA job — as opposed to a *preview*, which is a throwaway build on
# the one shared `*.preview.frever.net` distribution. It has nothing to do with the prod
# environment; both run there.
#
# Lovable does not commit image bytes. It commits a `<name>.<ext>.asset.json` sidecar and the app
# imports THE JSON, so the built bundle asks for a site-relative "/__l5e/assets-v1/<id>/<file>".
# On Lovable's hosting their edge answers that path. On ours nothing did, and every such image
# 404'd silently — the build succeeds, the page renders, and a broken <img> is not an error anyone
# is watching. Two migrations shipped COMPLETED that way on 2026-09-19.
#
# Phase 7 copies the bytes into the CUSTOMER'S OWN Supabase project, under
# `builder-assets/lovable/...`, with the key deliberately mirroring the URL path after "/__l5e/" so
# the route is a pure prefix swap. The repo is left byte-identical to Lovable's — nothing to revert
# on their side, and the same commit stays correct on both hosts.
#
# NOTHING IS COPIED HERE. Phase 7 already moved the bytes, once, into the customer's own Supabase
# project — that is the whole point of the migration. This file only routes at them.
#
# WHY A SECOND ORIGIN HERE, AND A REDIRECT ON THE PREVIEW DISTRIBUTION
#
# A CloudFront origin is a fixed domain. That one fact decides both designs. This distribution
# serves exactly ONE tenant, so its origin can simply BE that tenant's Supabase project and the
# bytes are proxied — same-origin to the browser, no extra round trip, cached at our edge. The
# shared `*.preview.frever.net` distribution cannot do that (one origin, 119 tenants), so it looks
# the tenant up in a KeyValueStore and 302s instead. Same rule, different constraint.
#
# And nothing is duplicated into S3. A SECOND copy of storage the customer already pays Supabase for
# would slow every deploy, go stale the moment they replace an asset, and — the version of this that
# was actually proposed — need a size cap, which means a site that silently shows FEWER images than
# it has. Proxying has no cap: gigabyte video streams fine.
#
# Entirely opt-in: `builder_asset_base_url` defaults to "" and every resource here is count = 0,
# so a site with no migrated builder media gets no origin, no behaviour and no function.

locals {
  builder_assets_enabled = var.builder_asset_base_url != ""

  # Split the base URL into the two parts CloudFront needs separately: an origin is a bare host,
  # and everything after it becomes `origin_path`, which CloudFront PREPENDS to the request URI.
  # regex() against an empty string would fail the plan outright, hence the guard value — it is
  # never reachable, because every resource below is also gated on builder_assets_enabled.
  builder_asset_url_safe = local.builder_assets_enabled ? var.builder_asset_base_url : "https://placeholder.invalid/x"

  builder_asset_host = regex("^https://([^/]+)", local.builder_asset_url_safe)[0]

  # No trailing slash: origin_path must not end in one, and the rewritten URI keeps its leading one.
  builder_asset_origin_path = trimsuffix(regex("^https://[^/]+(/.*)$", local.builder_asset_url_safe)[0], "/")
}

# Strips the "/__l5e" marker so `origin_path` can supply the real Supabase storage path:
#
#   viewer  /__l5e/assets-v1/<id>/hero.jpg
#   here    /assets-v1/<id>/hero.jpg
#   origin  /storage/v1/object/public/builder-assets/lovable/assets-v1/<id>/hero.jpg
#
# Deliberately NOT folded into the existing `viewer_request` function. That one runs on every
# request to the site, so a fault in it takes the whole site down; this is attached only to the
# "/__l5e/*" behaviour, so its blast radius is exactly the feature it implements.
resource "aws_cloudfront_function" "builder_assets" {
  count = local.builder_assets_enabled ? 1 : 0

  name    = "builder-assets-${substr(sha1("${var.account_name}-${local.domain_part}"), 0, 10)}"
  runtime = "cloudfront-js-2.0"
  comment = "Strip /__l5e so the builder-assets origin path applies"

  lifecycle {
    create_before_destroy = true
  }

  code = <<-JS
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var prefix = '/__l5e/';

    if (uri.indexOf(prefix) !== 0) {
        return notFound();
    }

    var key = uri.substring(prefix.length);
    // Belt-and-braces: CloudFront has already normalised the URI, so a traversal never reaches
    // here. This guards a pre-encoded request, and keeps the same rule as the Cloudflare dispatch
    // Worker's serveLovableAsset.
    if (!key || key.indexOf('..') !== -1) {
        return notFound();
    }

    request.uri = '/' + key;
    return request;
}

// A miss answers 404 rather than falling through to the S3 origin, which would hand back the SPA's
// index.html with a 200 — a broken image no monitoring notices, i.e. the original defect.
function notFound() {
    return {
        statusCode: 404,
        statusDescription: 'Not Found',
        headers: { 'content-type': { value: 'text/plain' } },
        body: 'Asset not found'
    };
}
JS
}

# The response half: restore the immutable cache header the other two hosting paths set.
#
# The asset id in the path changes whenever the bytes do, so Supabase's own `max-age=3600` is
# needlessly conservative and every revalidation is egress on the customer's bill. CloudFront's own
# cache TTL was decided from the origin's headers long before this point, so this governs the
# browser — which is where the win is, and it matches what the Cloudflare Worker and the preview
# redirect both set.
#
# WHAT THIS DELIBERATELY DOES *NOT* DO, AND WHY THAT TURNED OUT TO BE FINE
#
# `custom_error_response` is a distribution-level CloudFront setting with no per-cache-behaviour
# override, and this module maps 403/404 to `/index.html` with a **200** for SPA routing. The fear
# was that a missed asset would therefore come back as the SPA shell with a 200 — a broken image no
# monitoring notices, i.e. the original defect through the back door. An earlier version of this
# function tried to undo that by rewriting such a response back to 404.
#
# That branch was removed on 2026-09-20 once two facts were established in prod:
#
#   1. Supabase answers a miss with HTTP **400**, not 404 — for a missing object in an existing
#      bucket (`{"code":"NoSuchKey"}`) and for a missing bucket (`{"code":"NoSuchBucket"}`) alike.
#      `error_response_codes` covers 403/404/500 and NOT 400, so `custom_error_response` never fires
#      on this path. The SPA shell is never substituted, and a miss reaches the viewer as a 400.
#   2. It could not have worked anyway. AWS: "If the origin returns an HTTP error of 400 and above,
#      the CloudFront Function will not run."
#      (docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/functions-event-structure.html)
#      A miss IS the origin returning >=400, so the branch was unreachable by construction.
#
# It also carried a real cost: it keyed on `text/html`, so an HTML asset under "/__l5e/" would have
# been turned into a spurious 404.
#
# IF SUPABASE EVER STARTS ANSWERING 404 INSTEAD OF 400, re-read fact 2 before re-adding anything
# here — a viewer-response function still will not see it. The fix would be to drop `404` from
# `error_response_codes` (S3 behind an OAI granting only s3:GetObject answers 403 for a missing key,
# never 404, so SPA routing rides the 403 rule alone).
resource "aws_cloudfront_function" "builder_assets_response" {
  count = local.builder_assets_enabled ? 1 : 0

  name    = "builder-assets-res-${substr(sha1("${var.account_name}-${local.domain_part}"), 0, 10)}"
  runtime = "cloudfront-js-2.0"
  comment = "Cache migrated builder assets immutably at the browser"

  lifecycle {
    create_before_destroy = true
  }

  code = <<-JS
function handler(event) {
    var response = event.response;

    // Immutable by construction: the asset id in the path changes whenever the bytes do. Only on a
    // real hit — caching an error for a year is how a transient miss becomes permanent. (A miss
    // never reaches this function at all; see the note above.)
    if (response.statusCode === 200 || response.statusCode === 304) {
        response.headers['cache-control'] = { value: 'public, max-age=31536000, immutable' };
    }
    return response;
}
JS
}
