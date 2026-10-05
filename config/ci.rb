CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Brakeman", "bin/brakeman --no-pager"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Browser", "bin/rails test:system"
end
