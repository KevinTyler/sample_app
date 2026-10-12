class AddDeliveryTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :deliveries, :delivered_at, :datetime
    add_index :deliveries, :provider_message_id
  end
end
