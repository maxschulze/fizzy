require "test_helper"

class Authentik::LoginTest < ActiveSupport::TestCase
  test "links an identity that already signed in by email" do
    identity = identities(:kevin)

    assert_no_difference [ -> { Identity.count }, -> { User.count } ] do
      login = authenticate(uid: "kevin-subject", email_address: identity.email_address, name: "Kevin")

      assert_equal identity, login.identity
      assert_equal users(:kevin), login.user
      assert_equal accounts("37s"), login.account
    end

    assert_equal "kevin-subject", identity.reload.authentik_uid
  end

  test "links on a mixed-case email address" do
    identity = identities(:kevin)

    assert_no_difference -> { Identity.count } do
      login = authenticate(uid: "kevin-subject", email_address: "Kevin@37Signals.COM")

      assert_equal identity, login.identity
    end
  end

  test "leaves both sign-in methods working after linking" do
    identity = identities(:kevin)
    authenticate(uid: "kevin-subject", email_address: identity.email_address)

    assert_equal identity, Identity.find_by(authentik_uid: "kevin-subject")
    assert_equal identity, Identity.find_by(email_address: identity.email_address)
  end

  test "provisions an identity and a membership in the sole account" do
    with_sole_account(accounts("37s")) do
      login = nil

      assert_difference [ -> { Identity.count }, -> { User.count } ], 1 do
        login = authenticate(uid: "new-subject", email_address: "sarah@example.com", name: "Sarah")
      end

      assert_equal "sarah@example.com", login.identity.email_address
      assert_equal "new-subject", login.identity.authentik_uid
      assert_equal accounts("37s"), login.account
      assert_equal "Sarah", login.user.name
    end
  end

  test "provisioned members skip the verification and naming steps" do
    with_sole_account(accounts("37s")) do
      login = authenticate(uid: "new-subject", email_address: "sarah@example.com", name: "Sarah")

      assert login.user.verified?
      assert login.user.setup?
    end
  end

  test "does not pick an account when several are active" do
    login = nil

    assert_difference -> { Identity.count }, 1 do
      assert_no_difference -> { User.count } do
        login = authenticate(uid: "new-subject", email_address: "sarah@example.com", name: "Sarah")
      end
    end

    assert_nil login.account
  end

  test "follows the subject when the email address changes in Authentik" do
    identities(:kevin).update! authentik_uid: "kevin-subject"

    assert_no_difference -> { Identity.count } do
      login = authenticate(uid: "kevin-subject", email_address: "kevin@example.com")

      assert_equal identities(:kevin), login.identity
      assert_equal "kevin@example.com", login.identity.email_address
    end
  end

  test "refuses an email address linked to a different Authentik account" do
    identities(:kevin).update! authentik_uid: "someone-elses-subject"

    login = Authentik::Login.new(authentik_auth_hash(uid: "kevin-subject", email_address: identities(:kevin).email_address))

    assert_not login.authenticate
    assert_equal [ "#{identities(:kevin).email_address} is already linked to a different Authentik account" ],
      login.errors.full_messages
    assert_equal "someone-elses-subject", identities(:kevin).reload.authentik_uid
  end

  test "refuses a changed email address that belongs to someone else" do
    kevin = identities(:kevin)
    kevin.update! authentik_uid: "kevin-subject"

    login = Authentik::Login.new(authentik_auth_hash(uid: "kevin-subject", email_address: identities(:david).email_address))

    assert_not login.authenticate
    assert_equal [ "#{identities(:david).email_address} already belongs to someone else here" ],
      login.errors.full_messages
    assert_equal "kevin@37signals.com", kevin.reload.email_address
  end

  test "refuses a response without a subject or an email address" do
    assert_not Authentik::Login.new(authentik_auth_hash(uid: nil)).authenticate
    assert_not Authentik::Login.new(authentik_auth_hash(email_address: nil)).authenticate
    assert_not Authentik::Login.new(nil).authenticate
  end

  test "falls back to the email address when Authentik sends no name" do
    with_sole_account(accounts("37s")) do
      login = authenticate(uid: "new-subject", email_address: "sarah@example.com")

      assert_equal "sarah@example.com", login.user.name
    end
  end

  private
    def authenticate(**auth_attributes)
      Authentik::Login.new(authentik_auth_hash(**auth_attributes)).tap do |login|
        assert login.authenticate, -> { login.errors.full_messages.to_sentence }
      end
    end
end
