class GmailReviewItemsController < ApplicationController
  def update
    item = GmailReviewItem.find(params[:id])
    if params[:dismiss] == "1"
      item.update!(resolved: true)
      redirect_to gmail_connection_path, notice: "Review item dismissed.", status: :see_other
      return
    end
    raise Gmail::Error.new("confirm_sales_import_first") unless params[:confirm_import] == "1"
    email = params[:customer_email].to_s.strip.downcase
    raise Gmail::Error.new("valid_customer_email_required") unless URI::MailTo::EMAIL_REGEXP.match?(email)
    Gmail::Importer.new(item.gmail_connection).import_review(item, email: email, name: params[:customer_name].presence || email)
    redirect_to gmail_connection_path, notice: "Selected message imported as a customer inquiry. Nothing was sent.", status: :see_other
  rescue Gmail::Error => error
    redirect_to gmail_connection_path, alert: error.code.humanize, status: :see_other
  end
end
