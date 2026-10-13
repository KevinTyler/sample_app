# The agent's hourly rounds over every active event (see Assistant::CheckIn).
class AgentCheckInJob < ApplicationJob
  queue_as :default

  def perform
    Assistant::CheckIn.run_all
  end
end
