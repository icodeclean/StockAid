class OrganizationsController < ApplicationController
  require_permission one_of: [:can_create_organization?, :can_update_organization?]
  active_tab "organizations"

  def index
  end

  def edit
    @organization = Organization.find params[:id]
    raise PermissionError unless current_user.can_update_organization_at?(@organization)
  end

  def update
    current_user.update_organization params
    redirect_to action: :index
  end

  def create
    current_user.create_organization params
    redirect_to action: :index
  end
end
