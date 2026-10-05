class ApplicationController < ActionController::Base
  before_action :prevent_caching
  before_action :require_operator
  helper_method :current_operator

  private

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def current_operator
    @current_operator ||= Operator.find_by(id: session[:operator_id]) if session[:operator_id]
  end

  def require_operator
    redirect_to new_session_path unless current_operator
  end
end
