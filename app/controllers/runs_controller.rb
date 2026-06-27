class RunsController < ApplicationController
  def create
    run = Run.active.latest_first.first || RuntimeAdapters::OpencodeDemo.start!(project_path: Rails.root.to_s)
    redirect_to run_path(run)
  end

  def show
    @run = Run.find(params[:id])
    @runs = Run.session_list
    @selected_passport = @run.selected_passport(params[:passport_id])
    @panel = %w[passport audit].include?(params[:panel]) ? params[:panel] : nil
  end
end
