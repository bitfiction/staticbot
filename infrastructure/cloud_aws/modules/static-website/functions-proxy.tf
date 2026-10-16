# Base44 function URLs on a customer's LIVE static site: "/functions/*" → the customer's Supabase.
#
# Base44 serves every backend function on the app's own domain at "/functions/<name>" (and a nested
# one at "/functions/v1/chat/completions"). Those URLs are public contract: payment providers post
# webhooks to them, API customers are told to use them as a base URL, and the app's own docs print
# them. After a migration the functions run on the customer's Supabase project at
# "https://<ref>.supabase.co/functions/v1/<name>" (nested ones through a generated router named
# after their folder — see tf-runner steps_base44.base44_router_routes). This file keeps the old
# URLs working by proxying, so moving the site off Base44 changes nothing for those callers.
#
#   viewer  https://<site>/functions/v1/chat/completions
#   here    /v1/chat/completions                          (function strips "/functions")
#   origin  https://<ref>.supabase.co/functions/v1/v1/chat/completions   (origin_path prepends)
#
# Entirely opt-in: `supabase_functions_url` defaults to "" and every resource here is count = 0.
# staticbot-app sets it only for Base44-origin templates — a Lovable SPA may own a "/functions" page.
#
# WHAT ENABLING IT CHANGES ABOUT SPA FALLBACK
#
# This module's default `error_response_codes` turn 403/404 from ANY origin into /index.html with a
# 200, and 500 into /500.html. CloudFront custom error responses are distribution-wide — there is no
# per-behaviour override — so behind this proxy an API 404 or 403 would reach the API client as the
# app's HTML shell with a 200, and a 500 would lose its JSON body. So when this route is on:
#   - no custom error responses are configured at all, and
#   - the viewer-request function serves the SPA shell itself (extensionless path → /index.html),
#     the same rule the shared preview distribution's router uses.
# The trade: a missing static FILE (a path with an extension) now gets S3's own 403 instead of the
# app shell. That is the honest answer, and it is what the preview distribution already does.
#
# Not cached, all methods, all viewer headers except Host (CloudFront sends the origin's own Host,
# which Supabase's gateway requires). Unverified until planned on a real distribution: that the
# managed AllViewerExceptHostHeader policy forwards Authorization (API keys, Supabase JWTs).

locals {
  functions_proxy_enabled = var.supabase_functions_url != ""

  # Same split as builder-assets.tf; the guard value is unreachable because everything below is
  # gated on functions_proxy_enabled too.
  functions_url_safe   = local.functions_proxy_enabled ? var.supabase_functions_url : "https://placeholder.invalid/functions/v1"
  functions_host       = regex("^https://([^/]+)", local.functions_url_safe)[0]
  functions_origin_path = regex("^https://[^/]+(/.*)$", local.functions_url_safe)[0]

  # AWS managed policies (IDs from the CloudFront developer guide, verified 2026-10-16). By ID, not a
  # data source, so customer accounts need no extra policy-read permission.
  managed_cache_policy_caching_disabled             = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  managed_origin_request_policy_all_viewer_no_host  = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

# Strips the "/functions" marker so origin_path supplies Supabase's "/functions/v1". Attached only to
# the "/functions/*" behaviour (same blast-radius argument as builder-assets.tf).
resource "aws_cloudfront_function" "functions_proxy" {
  count = local.functions_proxy_enabled ? 1 : 0

  name    = "functions-proxy-${substr(sha1("${var.account_name}-${local.domain_part}"), 0, 10)}"
  runtime = "cloudfront-js-2.0"
  comment = "Strip /functions so the Supabase functions origin path applies"

  lifecycle {
    create_before_destroy = true
  }

  code = <<-JS
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var prefix = '/functions/';

    if (uri.indexOf(prefix) !== 0) {
        return notFound();
    }
    var rest = uri.substring(prefix.length);
    if (!rest || rest.indexOf('..') !== -1) {
        return notFound();
    }
    request.uri = '/' + rest;
    return request;
}

function notFound() {
    return {
        statusCode: 404,
        statusDescription: 'Not Found',
        headers: { 'content-type': { value: 'application/json' } },
        body: '{"error":"No function at this path"}'
    };
}
JS
}
