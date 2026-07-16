# static-website/redirects.tf

## Critical Rules
- The `viewer_request` CloudFront Function handles THREE concerns, in this priority order: maintenance mode → per-stack redirects → www canonicalisation → directory-index rewrite. Do not reorder. Maintenance must always win (otherwise legacy 301s would route past the maintenance page); redirects must precede www-redirect and clean-URL rewrite (otherwise a `/old-path` would be rewritten to `/old-path.html` and fall through to S3's 404 before the 301 fires).
- `var.redirects` is injected via `${jsonencode(var.redirects)}` and consumed as a JS array literal. CloudFront Functions runtime 2.0 is required for the `for` loop syntax; do not downgrade.
- The function emits the correct `statusDescription` per status code: 301 = "Moved Permanently", 307 = "Temporary Redirect", 308 = "Permanent Redirect", everything else = "Found". Keep this mapping in sync with `RedirectsParser`'s allowed status set (301/302/307/308).
- `lifecycle { create_before_destroy = true }` is mandatory for in-place function updates without downtime.
- The function name uses a 10-char sha1 prefix of `${account_name}-${domain_part}` for AWS-wide uniqueness — do not change the hash length or scheme; existing distributions are bound to existing names.

## Overview
Two CloudFront Functions:

1. **`language_redirect`** (cloudfront-js-1.0) — legacy geo-based language routing. Not wired to the `redirects` feature; only fires for sites that explicitly attach it.
2. **`viewer_request`** (cloudfront-js-2.0) — the main viewer-request handler. Handles maintenance, redirects, www canonicalisation, and directory-index rewriting in one function.

## Per-Stack Redirects

Configured via `var.redirects`, type `list(object({from=string, to=string, status=number}))`, default `[]`.

```hcl
variable "redirects" {
  type = list(object({
    from   = string
    to     = string
    status = number
  }))
  default = []
}
```

The list is injected at apply-time via `jsonencode` into the JS function body and iterated on every request. Matches are exact-string only — no wildcards or splats in v1.

End-to-end pipeline (from operator action to CloudFront):

```
Stack edit UI (RedirectsEditor.vue, Netlify _redirects format)
  → StacksResource validates via RedirectsParser
  → stack_templates.config_overrides JSONB: "redirects": "<raw text>"
  → On deployment: DeploymentService.applyInputTypeTransforms
      parses text → emits HCL list-of-objects string in worker job vars
  → tf-runner substitutes `redirects = <redirects>` in tfvars
  → terraform apply → this module → CloudFront Function update
```

## Adding new redirect types
- **Splats / wildcards** (`/old/*` → `/new/:splat`): extend `RedirectsParser` to recognise a trailing `*`, change the JS loop to do prefix-match alongside exact-match before falling through.
- **Force flag** (Netlify's `!`, redirect even when destination exists): not applicable here — every redirect is exact-match against the request URI before any S3 lookup, so destination existence is irrelevant.
- **Per-status defaults**: edit the `statusDescription` mapping in the heredoc.

## Pitfalls
- Adding a new variable used inside the heredoc requires it to be declared in `variables.tf` AND plumbed through the root module (`root_modules/static_website_custom_domain/{variables,locals,main}.tf`) AND both per-template wrappers (`_templates/static_website_infra_template/` + `_templates/static_website_on_subdomain_infra_template/`). Missing any layer makes the value silently default to the heredoc's hardcoded fallback.
- The Python tf-runner does literal string substitution on the tfvars file. The substituted value MUST be valid HCL (uses `=`), not JSON syntax. The Java backend pre-formats it via `RedirectsParser.toHclList`.
- The fallback safety net in `tf-runner/template.py` strips lines with unresolved `<placeholder>` patterns. If you add a placeholder but don't always emit its value, you'll get terraform-default behaviour instead of a clear failure.
