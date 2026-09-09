class Sessions::AuthentiksController < ApplicationController
  disallow_account_scope
  require_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limit_exceeded
  before_action :ensure_authentik_configured

  layout "public"

  def create
    login = Authentik::Login.new(request.env["omniauth.auth"])

    if login.authenticate
      start_new_session_for login.identity
      redirect_to_account_for login
    else
      redirect_to new_session_path, alert: login.errors.full_messages.to_sentence
    end
  end

  def failure
    redirect_to new_session_path, alert: "We couldn't sign you in with #{Authentik.label}. Please try again."
  end

  private
    def ensure_authentik_configured
      redirect_to new_session_path unless Authentik.configured?
    end

    def redirect_to_account_for(login)
      if login.account
        redirect_to landing_url(script_name: login.account.slug)
      elsif Account.accepting_signups?
        redirect_to new_signup_completion_url(script_name: nil)
      else
        # Signed in, but with no account to enter and none they may create, so
        # leave them on the account picker. An admin has to invite them.
        redirect_to session_menu_url(script_name: nil),
          alert: "You're signed in, but you don't have access to an account yet. Ask an admin to invite you."
      end
    end

    def rate_limit_exceeded
      redirect_to new_session_path, alert: "Try again later."
    end
end
