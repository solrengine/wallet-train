Solrengine::Auth.configure do |config|
  config.domain = ENV.fetch("APP_DOMAIN", "localhost")
  config.nonce_ttl = 5.minutes
  config.after_sign_in_path = "/dashboard"
  config.after_sign_out_path = "/"
end
