class AuditEventsController < ApplicationController
  def index
    @run = Run.find(params[:run_id])
    @audit_events = @run.audit_events.chronological

    if turbo_frame_request?
      render partial: "runs/audit_timeline", locals: { run: @run, audit_events: @audit_events }
    else
      redirect_to run_path(@run, panel: "audit")
    end
  end
end
