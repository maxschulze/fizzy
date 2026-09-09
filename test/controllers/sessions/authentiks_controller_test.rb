require "test_helper"

class Sessions::AuthentiksControllerTest < ActionDispatch::IntegrationTest
  test "signing in an identity that already exists" do
    identity = identities(:kevin)

    sign_in_with_authentik uid: "kevin-subject", email_address: identity.email_address

    assert cookies[:session_token].present?
    assert_redirected_to landing_url(script_name: accounts("37s").slug)
    assert_equal identity, Session.last.identity
  end

  test "provisioning a new identity into the sole account" do
    with_sole_account(accounts("37s")) do
      assert_difference [ -> { Identity.count }, -> { User.count }, -> { Session.count } ], 1 do
        sign_in_with_authentik uid: "new-subject", email_address: "sarah@example.com", name: "Sarah"
      end

      assert_redirected_to landing_url(script_name: accounts("37s").slug)
    end
  end

  test "sending someone with no membership to finish signing up" do
    sign_in_with_authentik uid: "new-subject", email_address: "sarah@example.com", name: "Sarah"

    assert cookies[:session_token].present?
    assert_redirected_to new_signup_completion_url(script_name: nil)
  end

  test "sending someone with no membership to the account picker when signups are closed" do
    with_multi_tenant_mode(false) do
      sign_in_with_authentik uid: "new-subject", email_address: "sarah@example.com", name: "Sarah"

      assert cookies[:session_token].present?
      assert_redirected_to session_menu_url(script_name: nil)
      assert_match "Ask an admin to invite you", flash[:alert]
    end
  end

  test "refusing a response Authentik linked to another account" do
    identities(:kevin).update! authentik_uid: "someone-elses-subject"

    assert_no_difference -> { Session.count } do
      sign_in_with_authentik uid: "kevin-subject", email_address: identities(:kevin).email_address
    end

    assert_nil cookies[:session_token].presence
    assert_redirected_to new_session_path(script_name: nil)
    assert_match "already linked to a different Authentik account", flash[:alert]
  end

  test "reporting a failed sign in" do
    untenanted do
      get authentik_failure_path

      assert_redirected_to new_session_path(script_name: nil)
      assert_match "couldn't sign you in with Authentik", flash[:alert]
    end
  end

  test "refusing the callback when Authentik isn't configured" do
    without_authentik do
      assert_no_difference -> { Session.count } do
        sign_in_with_authentik uid: "new-subject", email_address: "sarah@example.com"
      end

      assert_redirected_to new_session_path(script_name: nil)
    end
  end

  test "redirecting an already authenticated request" do
    sign_in_as :kevin

    untenanted do
      get authentik_callback_path

      assert_redirected_to root_url
    end
  end
end
