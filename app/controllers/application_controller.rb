class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :authenticate!

  helper_method :current_user, :logged_in?, :current_network, :current_rpc_url

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def authenticate!
    redirect_to login_path unless logged_in?
  end

  def current_network
    session[:network] || "mainnet"
  end

  def current_rpc_url
    SolanaConfig.rpc_url(current_network)
  end
end
