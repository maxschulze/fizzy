module AuthentikTestHelper
  # Authentik is configured for the whole test env (see config/environments/test.rb)
  # so its middleware is mounted. These helpers scope the parts a test varies.

  def authentik_auth_hash(uid: "authentik-subject", email_address: "new@example.com", name: nil)
    OmniAuth::AuthHash.new \
      provider: Authentik::PROVIDER.to_s,
      uid: uid,
      info: { email: email_address, email_verified: true, name: name }.compact
  end

  # Walks the callback the way the browser does, with Authentik's response mocked.
  def sign_in_with_authentik(**auth_attributes)
    with_authentik_auth(**auth_attributes) do
      untenanted { get authentik_callback_path }
    end
  end

  def with_authentik_auth(**auth_attributes)
    previous = OmniAuth.config.mock_auth[Authentik::PROVIDER]
    begin
      OmniAuth.config.mock_auth[Authentik::PROVIDER] = authentik_auth_hash(**auth_attributes)
      yield
    ensure
      OmniAuth.config.mock_auth[Authentik::PROVIDER] = previous
    end
  end

  def without_authentik
    with_authentik_settings(issuer: nil, client_id: nil, client_secret: nil) { yield }
  end

  def with_authentik_only
    with_authentik_settings(only: true) { yield }
  end

  # Auto-provisioning only applies when there's exactly one active account, the
  # self-hosted shape. Fixtures ship three, so cancel the others.
  def with_sole_account(account)
    others = Account.where.not(id: account).to_a
    begin
      others.each { |other| other.create_cancellation!(initiated_by: users(:jason)) }
      yield
    ensure
      Account::Cancellation.where(account: others).destroy_all
    end
  end

  def with_authentik_settings(**settings)
    previous = settings.keys.index_with { |name| Rails.application.config.x.authentik.send(name) }
    begin
      settings.each { |name, value| Rails.application.config.x.authentik.send("#{name}=", value) }
      yield
    ensure
      previous.each { |name, value| Rails.application.config.x.authentik.send("#{name}=", value) }
    end
  end
end
