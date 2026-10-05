class SessionsController < ApplicationController
  skip_before_action :require_operator, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Too many attempts. Please try again shortly." }

  def new
  end

  def create
    operator = Operator.find_by(email: params[:email].to_s.strip.downcase)
    if operator&.authenticate(params[:password])
      reset_session
      session[:operator_id] = operator.id
      redirect_to root_path
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end
end
