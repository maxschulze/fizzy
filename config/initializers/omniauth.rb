# Mounts the Authentik strategy when it's configured. Reads config.x directly
# rather than through Authentik, so no app model is autoloaded during boot.
authentik = Rails.application.config.x.authentik

if authentik.issuer.present? && authentik.client_id.present? && authentik.client_secret.present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :oidc,
      name: :authentik,
      scope: authentik.scopes.to_s.split,
      pkce: true,
      client_options: {
        identifier: authentik.client_id,
        secret: authentik.client_secret,
        config_endpoint: "#{authentik.issuer.chomp("/")}/.well-known/openid-configuration"
      }
  end
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.path_prefix = "/auth"
OmniAuth.config.allowed_request_methods = [ :post ]

# OmniAuth builds the redirect URI from the request host unless we pin it, and
# Authentik will only redirect to the one URI it was configured with.
OmniAuth.config.full_host = ENV["BASE_URL"].presence

# The app protects forgery with Sec-Fetch-Site rather than form tokens (see
# RequestForgeryProtection), so mirror that here instead of reaching for
# omniauth-rails_csrf_protection, which expects an authenticity token.
OmniAuth.config.request_validation_phase = ->(env) do
  unless env["HTTP_SEC_FETCH_SITE"].in?([ nil, "same-origin", "none" ])
    raise OmniAuth::AuthenticityError
  end
end
