# Authentik (OpenID Connect) single sign-on, offered alongside the email and
# passkey sign-ins. Absent AUTHENTIK_ISSUER, AUTHENTIK_CLIENT_ID and
# AUTHENTIK_CLIENT_SECRET the feature is simply off and nothing changes.
#
# Settings come from ENV, falling back to config.x.authentik so the test env
# (and any deployment that wraps Fizzy in an engine) can configure them without
# environment variables. Same shape as the CSP initializer.
#
# ENV vars:
#   AUTHENTIK_ISSUER        The provider's OpenID Configuration URL, minus the
#                           .well-known/openid-configuration suffix. Not the
#                           "OpenID Configuration Issuer" field, which differs
#                           under Authentik's global issuer mode.
#                           e.g. https://auth.example.com/application/o/fizzy/
#   AUTHENTIK_CLIENT_ID     The provider's client ID
#   AUTHENTIK_CLIENT_SECRET The provider's client secret
#   AUTHENTIK_LABEL         Name to show on the sign-in button (default "Authentik")
#   AUTHENTIK_SCOPES        Scopes to request (default "openid email profile")
#   AUTHENTIK_ONLY          "true" closes email sign-in and signup; passkeys stay
#   AUTHENTIK_SIGN_OUT_URL  Authentik's end-session URL. When set, signing out
#                           of Fizzy signs you out of Authentik too.
#
# BASE_URL must also be set, since Authentik has to be told a fixed redirect URI
# and OmniAuth builds it from that host.

Rails.application.configure do
  setting = ->(name, default = nil) do
    env_key = "AUTHENTIK_#{name.to_s.upcase}"

    if ENV.key?(env_key)
      ENV[env_key].presence
    else
      config.x.authentik.send(name)
    end || default
  end

  config.x.authentik.issuer = setting.(:issuer)
  config.x.authentik.client_id = setting.(:client_id)
  config.x.authentik.client_secret = setting.(:client_secret)
  config.x.authentik.label = setting.(:label, "Authentik")
  config.x.authentik.scopes = setting.(:scopes, "openid email profile")
  config.x.authentik.sign_out_url = setting.(:sign_out_url)
  config.x.authentik.only = setting.(:only).to_s == "true"

  # Browsers enforce form-action against every hop of a form submission's
  # redirect chain, and the sign-in button posts to a path that redirects out
  # to the provider. The CSP therefore has to name the provider's origin, so
  # derive it here, next to the setting it comes from.
  config.x.authentik.origin = begin
    if (issuer = config.x.authentik.issuer).present?
      uri = URI.parse(issuer)
      port = ":#{uri.port}" unless uri.port == uri.default_port
      "#{uri.scheme}://#{uri.host}#{port}" if uri.scheme && uri.host
    end
  rescue URI::InvalidURIError
    nil
  end
end
