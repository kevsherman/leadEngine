class ConversationsController < ApplicationController
  def index
    @conversations = Conversation.queue(search: params[:search], status: params[:status])
  end

  def show
    @conversations = Conversation.queue(search: params[:search], status: params[:status])
    @conversation = Conversation.find(params[:id])
    @draft = @conversation.email_draft
  end
end
