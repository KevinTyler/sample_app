class ScheduleReply < ApplicationRecord
  belongs_to :schedule_item
  belongs_to :guest
end
