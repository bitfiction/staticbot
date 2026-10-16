# Plan-only checks for functions-proxy.tf with mocked AWS providers (no account, no network).
# Run from this module: tofu init && tofu test
mock_provider "aws" {
  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/mock"
    }
  }
}
mock_provider "aws" {
  alias = "certificates"
}

variables {
  account_name    = "acct"
  domain_name     = "example.com"
  zone_id         = "Z123"
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
  stage_subdomain = "www"
  content_path    = "./tests/fixture"
}

run "off_by_default_the_distribution_is_unchanged" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_function.functions_proxy) == 0
    error_message = "no proxy function without supabase_functions_url"
  }
  assert {
    condition     = length(aws_cloudfront_distribution.website.origin) == 1
    error_message = "only the S3 origin"
  }
  assert {
    condition     = length(aws_cloudfront_distribution.website.custom_error_response) == 3
    error_message = "the SPA error mapping (403/404/500) stays on for every other site"
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var spaShellInFunction = false;")
    error_message = "viewer-request keeps its directory-index behaviour"
  }
}

run "on_proxies_functions_and_moves_spa_fallback_into_the_function" {
  command = plan

  variables {
    supabase_functions_url = "https://vtbxidqshrkbeewpqeaq.supabase.co/functions/v1"
  }

  assert {
    condition     = length(aws_cloudfront_function.functions_proxy) == 1
    error_message = "proxy function expected"
  }
  assert {
    condition = anytrue([for o in aws_cloudfront_distribution.website.origin :
      o.origin_id == "supabase-functions" && o.domain_name == "vtbxidqshrkbeewpqeaq.supabase.co" && o.origin_path == "/functions/v1"])
    error_message = "Supabase functions origin with origin_path /functions/v1"
  }
  assert {
    condition = anytrue([for b in aws_cloudfront_distribution.website.ordered_cache_behavior :
      b.path_pattern == "/functions/*" && b.target_origin_id == "supabase-functions"
      && contains(b.allowed_methods, "POST")
      && b.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      && b.origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac"])
    error_message = "/functions/* behaviour: all methods, CachingDisabled, AllViewerExceptHostHeader"
  }
  assert {
    condition     = length(aws_cloudfront_distribution.website.custom_error_response) == 0
    error_message = "no distribution-wide error mapping: it would replace API errors with the SPA shell"
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var spaShellInFunction = true;")
    error_message = "viewer-request serves the SPA shell itself"
  }
}

run "rejects_a_url_that_is_not_the_functions_base" {
  command = plan

  variables {
    supabase_functions_url = "https://vtbxidqshrkbeewpqeaq.supabase.co"
  }

  expect_failures = [var.supabase_functions_url]
}
