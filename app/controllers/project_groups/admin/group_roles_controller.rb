# frozen_string_literal: true

#-- copyright
# OpenProject Project Groups plugin.
# Copyright (C) 2026 Neri Guidi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.md and doc/GPL.txt for more details.
#++

module ProjectGroups
  module Admin
    # Global admin screen to define each (native) group's role-set — the project
    # roles a group grants. Admin-only for now (a global `manage_project_group_roles`
    # permission could replace require_admin later, README §9.3).
    class GroupRolesController < ApplicationController
      layout "admin"

      before_action :require_admin
      before_action :find_group, only: %i[edit update]

      menu_item :project_group_roles

      def index
        @groups = Group.not_organizational_units.order(:lastname)
      end

      def edit
        @selectable_roles = selectable_roles
        @selected_role_ids = @group.project_group_roles.pluck(:role_id)
      end

      def update
        ProjectGroups::SetGroupRoleSet.call(group: @group, role_ids: params[:role_ids])
        flash[:notice] = t("project_groups.admin.flash.saved")
        redirect_to project_groups_admin_group_roles_path, status: :see_other
      end

      private

      def find_group
        @group = Group.find(params[:id])
      end

      # Only roles valid for a project member (what reconciliation will accept).
      def selectable_roles
        Role.all.select(&:member?).sort_by(&:name)
      end
    end
  end
end
