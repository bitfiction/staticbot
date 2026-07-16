# Tests for the `account_name` validation rule in variables.tf.
#
# These tests do not need a real Cloudflare provider -- the validation runs at
# variable-resolution time, before any provider call. We use `mock_provider` so
# `tofu test` doesn't attempt network calls.
#
# Run from this directory:
#   tofu init -backend=false
#   tofu test

mock_provider "cloudflare" {}

# Shared default vars for the runs below. Each run can override `account_name`
# (the field under test) without re-specifying the others.
variables {
  account_name = "valid-name"

  cloudflare_account = {
    account_id = "cf-acc-yyy"
    api_token  = "cf-token-xxx"
  }

  shared_infra = {
    dispatch_namespace_name = "staticbot-apps-prod"
    dispatch_namespace_id   = "ns-id-123"
    routes_kv_namespace_id  = "kv-id-456"
    zone_id                 = "zone-id-789"
    fallback_hostname       = "apps.staticbot.app"
  }

  app = {
    worker_name       = "acme-app"
    customer_hostname = "app.acme.com"
    plain_env         = {}
  }
}

run "accepts_valid_short_name" {
  command = plan

  variables {
    account_name = "abc"
  }
}

run "accepts_lowercase_alphanumeric_with_hyphens" {
  command = plan

  variables {
    account_name = "staticbot-acme-prod"
  }
}

run "accepts_max_length_63_chars" {
  command = plan

  variables {
    # 63 chars exactly: the boundary of what's allowed.
    # 5 × "abcdefghij-" (55) + "12345678" (8) = 63.
    account_name = "abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij-12345678"
  }
}

run "rejects_uppercase" {
  command = plan

  variables {
    account_name = "Staticbot-Acme"
  }

  expect_failures = [var.account_name]
}

run "rejects_dots" {
  command = plan

  variables {
    account_name = "acme.staticbot.app"
  }

  expect_failures = [var.account_name]
}

run "rejects_underscores" {
  command = plan

  variables {
    account_name = "staticbot_acme_prod"
  }

  expect_failures = [var.account_name]
}

run "rejects_too_long" {
  command = plan

  variables {
    # 64 chars: one over the 63-char limit (S3 bucket / TF backend key constraint).
    # 5 × "abcdefghij-" (55) + "123456789" (9) = 64.
    account_name = "abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij-123456789"
  }

  expect_failures = [var.account_name]
}

run "rejects_empty" {
  command = plan

  variables {
    account_name = ""
  }

  expect_failures = [var.account_name]
}
