# Development only: a phone simulator for the texting assistant. Messages go through the same
# pipeline as real texts; replies land in the dev outbox and show in the thread.
class Dev::AssistantController < ApplicationController
  allow_unauthenticated_access

  def show
    @phone = phone
    @conversation = AssistantConversation.find_by(channel: channel, address: @phone)
    @messages = @conversation ? @conversation.recent_messages(60) : []
    @provider = Assistant::ClaudeBrain.available? ? "Claude (#{Assistant::ClaudeBrain::MODEL})" : "guided mode — set ANTHROPIC_API_KEY for Claude"
  end

  def create
    media = []
    if params[:media].respond_to?(:content_type)
      blob = ActiveStorage::Blob.create_and_upload!(io: params[:media], filename: params[:media].original_filename,
        content_type: params[:media].content_type)
      media << { "url" => "outbox:#{blob.signed_id}", "content_type" => blob.content_type }
    end
    Assistant::Inbound.receive(channel: channel, address: phone, body: params[:body], media: media, reply_now: true)
    redirect_to dev_assistant_path(phone: phone, channel: channel)
  end

  private
    def phone
      PhoneNumber.normalize(params[:phone].presence || "+15550123") || "+15550123"
    end

    def channel
      params[:channel].presence_in(AssistantConversation::CHANNELS) || "sms"
    end
end
