class DashboardsController < ApplicationController
  def show
    @run = Run.current
    @runs = Run.session_list
    @selected_passport = @run&.selected_passport(params[:passport_id])
    @panel = %w[passport audit].include?(params[:panel]) ? params[:panel] : nil

    render "runs/show" if @run.present?
  end
end
