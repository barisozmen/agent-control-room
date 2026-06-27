class PermissionRequestsController < ApplicationController
  def show
    permission_request = PermissionRequest.includes(:tool_action, :run).find(params[:id])
    authenticate_bridge_or_machine_token!(permission_request.run)

    render json: permission_request.bridge_payload
  rescue ActiveRecord::RecordNotFound => error
    render json: { ok: false, error: error.message }, status: :not_found
  end
end
