class AddAuthentikUidToIdentities < ActiveRecord::Migration[8.2]
  def change
    add_column :identities, :authentik_uid, :string, limit: 255
    add_index :identities, :authentik_uid, unique: true
  end
end
