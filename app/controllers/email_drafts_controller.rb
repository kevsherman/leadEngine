class EmailDraftsController < ApplicationController
  before_action :set_draft
  rescue_from ActiveRecord::StaleObjectError, ReplyWorkflow::InvalidTransition, with: :workflow_error

  def update
    @draft.with_lock do
      raise ReplyWorkflow::InvalidTransition, "This reply is locked for sending." unless @draft.editable?
      @draft.update!(params.require(:email_draft).permit(:to, :cc, :subject, :body, :lock_version))
      @draft.conversation.audit_events.create!(action: "draft_saved", operator: current_operator)
    end
    redirect_to conversation_path(@draft.conversation), notice: "Draft saved. Review it before approval.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to conversation_path(@draft.conversation), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  def review
  end

  def approve
    ReplyWorkflow.approve(@draft, current_operator, params[:lock_version])
    redirect_to conversation_path(@draft.conversation), notice: "Exact saved reply approved. Sending still requires your explicit action.", status: :see_other
  end

  def send_reply
    ReplyWorkflow.enqueue(@draft, current_operator, params[:lock_version], confirm_live: params[:confirm_live] == "1")
    redirect_to conversation_path(@draft.conversation), notice: @draft.conversation.email_provider == "gmail" ? "Approved Gmail reply queued for the worker." : "Simulated reply queued for the worker.", status: :see_other
  end

  def reconcile
    operation = @draft.send_operation
    raise ReplyWorkflow::InvalidTransition, "This reply has no uncertain Gmail send." unless operation&.provider == "gmail" && %w[sending unknown].include?(operation.status)
    GmailReconcileJob.perform_later(operation.id)
    redirect_to conversation_path(@draft.conversation), notice: "Checking Gmail Sent mail. No email will be resent.", status: :see_other
  end

  def new_reply
    conversation = @draft.conversation
    conversation.with_lock do
      raise ReplyWorkflow::InvalidTransition, "Resolve the current send before starting another reply." unless %w[sent blocked cancelled failed].include?(conversation.email_draft.status)
      previous = conversation.email_draft
      if previous.status != "sent"
        previous.send_operation&.with_lock { previous.send_operation.update!(status: "cancelled") }
        previous.update!(status: "cancelled")
      end
      conversation.create_email_draft!(to: conversation.customer_email, subject: @draft.subject,
        body: "Hi #{conversation.customer_name},\n\n[Write your reply here.]\n\nBest,\nKevin\nBreeze Block Canada")
    end
    redirect_to conversation_path(conversation), status: :see_other
  end

  private

  def set_draft
    @draft = EmailDraft.find(params[:id])
  end

  def workflow_error(error)
    redirect_to conversation_path(@draft.conversation), alert: error.message, status: :see_other
  end
end
