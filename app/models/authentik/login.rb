# Turns a successful Authentik callback into an Identity to start a session for.
#
# Identity is the join point: it's global and keyed by email address, so someone
# who already signed into Fizzy by email or passkey resolves to that same
# Identity and keeps every user, board, comment and notification hanging off it.
# We pin Authentik's subject onto it on first use, which both links the two
# accounts and lets a later email change in Authentik follow the same Identity
# instead of quietly making a second one.
class Authentik::Login
  include ActiveModel::Model

  attr_reader :uid, :email_address, :name, :identity, :user

  validates :uid, :email_address, presence: { message: "was missing from the sign-in response" }
  validate :email_address_is_not_linked_to_another_authentik_account
  validate :email_address_is_not_already_taken

  def initialize(auth)
    auth = (auth || {}).to_h.with_indifferent_access

    @uid = auth[:uid].presence
    @email_address = Identity.normalize_value_for(:email_address, auth.dig(:info, :email))
    @name = auth.dig(:info, :name).presence || @email_address
  end

  def authenticate
    if valid?
      Identity.transaction do
        @identity = link_identity
        @user = provision_membership
      end

      true
    else
      false
    end
  end

  def account
    user&.account
  end

  private
    def email_address_is_not_linked_to_another_authentik_account
      if identity_by_uid.nil? && identity_by_email&.authentik_uid.present?
        errors.add :base, "#{email_address} is already linked to a different #{Authentik.label} account"
      end
    end

    def email_address_is_not_already_taken
      if identity_by_uid && identity_by_email && identity_by_uid != identity_by_email
        errors.add :base, "#{email_address} already belongs to someone else here"
      end
    end

    def identity_by_uid
      return @identity_by_uid if defined?(@identity_by_uid)
      @identity_by_uid = Identity.find_by(authentik_uid: uid) if uid.present?
    end

    def identity_by_email
      return @identity_by_email if defined?(@identity_by_email)
      @identity_by_email = Identity.find_by(email_address: email_address) if email_address.present?
    end

    def link_identity
      if identity = identity_by_uid
        identity.tap { it.update!(email_address: email_address) unless it.email_address == email_address }
      elsif identity = identity_by_email
        identity.tap { it.update!(authentik_uid: uid) }
      else
        Identity.create!(email_address: email_address, authentik_uid: uid)
      end
    end

    # Sign into the membership they already have, or join them to the account
    # when there's exactly one — the self-hosted shape. With several accounts
    # there's no defensible one to pick, so they fall through to signup instead
    # of landing in a stranger's account.
    def provision_membership
      identity.users_with_active_accounts.first || join_sole_account
    end

    def join_sole_account
      if account = sole_account
        identity.join account, name: name, verified_at: Time.current
        account.users.find_by!(identity: identity)
      end
    end

    def sole_account
      Current.without_account { Account.active.first if Account.active.one? }
    end
end
