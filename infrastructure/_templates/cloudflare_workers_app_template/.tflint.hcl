plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "cloudflare" {
  enabled = true
  version = "0.4.0"
  source  = "github.com/terraform-linters/tflint-ruleset-cloudflare"
}

# Catch hand-tuned but easy-to-miss things:
config {
  force = false
}
