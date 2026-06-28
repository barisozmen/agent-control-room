class GrantsController < ApplicationController
  def destroy
    @run = Run.find(params[:run_id])
    @passport = @run.passports.find(params[:passport_id])
    grant = @passport.grants.find(params[:id])
    revoke_grant!(grant)

    @run.broadcast_control_room!(selected_passport: @passport)

    respond_to do |format|
      format.html { redirect_to run_path(@run, passport_id: @passport.id, panel: "passport"), notice: "Passport grant revoked." }
      format.turbo_stream
    end
  end

  private

  def revoke_grant!(grant)
    capability = grant.capability
    pattern = grant.pattern
    permission_request = grant.permission_request

    Grant.transaction do
      grant.destroy!
      AuditEvent.create!(
        run: @run,
        passport: @passport,
        permission_request: permission_request,
        event_kind: "permission.grant_revoked",
        actor_lineage: @passport.lineage_label,
        capability: capability,
        action_summary: "Revoked #{capability} passport grant: #{pattern}",
        decision: "revoke",
        result: "revoked",
        occurred_at: Time.current
      )
    end
  end
end
