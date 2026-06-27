class PassportsController < ApplicationController
  def show
    @run = Run.find(params[:run_id])
    @passport = @run.passports.find(params[:id])

    if turbo_frame_request?
      render partial: "runs/passport_detail", locals: { run: @run, passport: @passport }
    else
      redirect_to run_path(@run, passport_id: @passport.id, panel: "passport")
    end
  end
end
