module Users
  module UserManipulator
    extend ActiveSupport::Concern
    attr_reader :original_email

    def can_invite_user?
      super_admin? || admin?
    end

    def can_invite_user_at?(organization)
      super_admin? || admin_at?(organization)
    end

    def can_delete_user?
      super_admin?
    end

    def can_update_user?(user = nil)
      if !user
        # Checking if this user has general access to update other users
        super_admin? || admin?
      elsif user == self
        # Users can always update themselves
        true
      else
        # Updating a specific user requires update user permission at that organization
        super_admin? || user.organizations.any? { |organization| can_update_user_at?(organization) }
      end
    end

    def can_update_user_details?(user)
      super_admin? || user == self
    end

    def can_update_user_role?(user)
      super_admin? || user.organizations.any? { |organization| can_update_user_role_at?(organization) }
    end

    def can_update_user_at?(organization)
      super_admin? || admin_at?(organization)
    end

    def can_update_user_role_at?(organization)
      can_update_user_at?(organization)
    end

    def invite_user(params)
      invitation = transaction do
        user_params = params.require(:user)
        organization = Organization.find(user_params[:organization_id])
        raise PermissionError unless can_invite_user_at?(organization)
        create_params = user_params.permit(:name, :email, :role)
        create_params[:organization] = organization
        UserInvitation.create_or_add_to_organization(self, create_params)
      end

      invitation.invite_mailer(self).deliver_now
    end

    def update_user(params)
      user = transaction do
        user = User.find(params[:id])
        raise PermissionError unless can_update_user?(user)
        user.update_details(params) if can_update_user_details?(user)
        user.update_roles(self, params) if can_update_user_role?(user)
        user
      end

      UserEmailChangedMailer.changed_email(user).deliver_now if user.email_updated?
    end

    def destroy_user(params)
      raise PermissionError unless can_delete_user?

      transaction do
        User.find(params[:id]).organization_users.each(&:destroy!)
      end
    end

    protected

    def email_updated?
      @email_updated
    end

    def update_details(params)
      return unless params[:user]
      @email_updated = params[:user].include?(:email) && email != params[:user][:email]
      @original_email = email
      update! params.require(:user).permit(:name, :email, :primary_number, :secondary_number)
    end

    def update_roles(updater, params)
      return unless params[:roles]

      params[:roles].each do |organization_id, role|
        organization = Organization.find(organization_id)
        next unless updater.can_update_user_at?(organization)

        if role.blank?
          organization_user_at(organization).destroy!
        else
          organization_user_at(organization).update! role: role
        end
      end
    end

    class_methods do
      def updateable_by(user)
        if user.super_admin?
          all
        else
          at_organization(user.organizations_with_permission_enabled(:can_update_user_at?))
        end
      end
    end
  end
end
