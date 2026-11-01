require "application_system_test_case"

class LiveUpdatesTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup do
    sign_in_as(users(:david))
    Current.user = users(:kevin)
  end

  test "board view shows a card moved elsewhere" do
    board = boards(:writebook)
    card = cards(:buy_domain)
    target_column = columns(:writebook_in_progress)

    visit board_url(board)
    within("#maybe") { assert_text card.title }

    move_card_elsewhere(card, target_column)

    within "##{dom_id(target_column)}" do
      assert_selector "##{dom_id(card, :article)}", visible: :all, wait: 5
    end
    within("#maybe") { assert_no_selector "##{dom_id(card, :article)}", visible: :all }
  end

  test "home view shows activity from elsewhere" do
    card = cards(:layout)

    visit root_url

    add_comment_elsewhere(card, "Fresh comment from another user")

    assert_text "Fresh comment from another user", wait: 5
  end

  test "card detail view shows a comment added elsewhere" do
    card = cards(:layout)

    visit card_url(card)

    add_comment_elsewhere(card, "Another user's comment")

    assert_text "Another user's comment", wait: 5
  end

  test "notifications tray shows a notification from elsewhere" do
    visit root_url

    create_notification_elsewhere

    assert_selector "#notifications", text: "RE: Layout is broken", visible: :all, wait: 5
  end

  test "notifications page shows a notification from elsewhere" do
    visit notifications_url

    create_notification_elsewhere

    assert_text "RE: Layout is broken", wait: 5
  end

  private
    def move_card_elsewhere(card, column)
      wait_for_cable_subscriptions
      card.triage_into(column)
      perform_enqueued_jobs only: Turbo::Streams::BroadcastStreamJob
    end

    def add_comment_elsewhere(card, body)
      wait_for_cable_subscriptions
      card.comments.create!(body: body, creator: Current.user)
      perform_enqueued_jobs only: Turbo::Streams::BroadcastStreamJob
    end

    def create_notification_elsewhere
      wait_for_cable_subscriptions
      Notification.create!(user: users(:david), source: events(:layout_commented), creator: Current.user)
      perform_enqueued_jobs only: [ Turbo::Streams::ActionBroadcastJob, Turbo::Streams::BroadcastStreamJob ]
    end

    # A broadcast sent before the page's subscriptions are confirmed is lost.
    def wait_for_cable_subscriptions
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      assert_no_selector "turbo-cable-stream-source:not([connected])", visible: :all
    end
end
