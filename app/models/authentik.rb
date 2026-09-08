# Reads the Authentik settings that config/initializers/authentik.rb collected.
# Everything here is request-time only, so the constant is never autoloaded
# while the app is still initializing.
module Authentik
  PROVIDER = :authentik

  class << self
    def configured?
      issuer.present? && client_id.present? && client_secret.present?
    end

    # True when Authentik is the only way in, and email sign-in and signup are
    # both closed. Recover from a misconfiguration by unsetting AUTHENTIK_ONLY
    # and restarting: a magic link won't help, since redeeming one needs the
    # pending authentication cookie that only the email flow sets.
    def only?
      configured? && settings.only
    end

    def issuer        = settings.issuer
    def client_id     = settings.client_id
    def client_secret = settings.client_secret
    def label         = settings.label
    def sign_out_url  = settings.sign_out_url if configured?

    def scopes
      settings.scopes.to_s.split
    end

    def discovery_endpoint
      "#{issuer.to_s.chomp("/")}/.well-known/openid-configuration"
    end

    # Owned by OmniAuth's middleware rather than by our routes, and deliberately
    # unprefixed: sign-in happens before we know which account you're heading
    # for, and Authentik is configured with one fixed redirect URI.
    def authorization_path
      "/auth/#{PROVIDER}"
    end

    def callback_path
      "#{authorization_path}/callback"
    end

    private
      def settings
        Rails.application.config.x.authentik
      end
  end
end
