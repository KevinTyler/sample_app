class HostDigestJob < ApplicationJob
  queue_as :default

  def perform
    HostNotifier.send_digests
  end
end
