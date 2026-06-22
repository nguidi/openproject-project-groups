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
    # Add/remove a single role to/from a (native) group's role-set. The UI is the
    # "Project roles" tab on the native Group page (app/views/groups/_project_group_roles.html.erb).
    # Admin-only. Both actions recompute the set and hand it to SetGroupRoleSet, which
    # diffs it and reconciles the affected members.
    class GroupRolesController < ApplicationController
      before_action :require_admin
      before_action :find_group

      def add_role
        apply_role_set(current_role_ids + [param_role_id])
      end

      def remove_role
        apply_role_set(current_role_ids - [param_role_id])
      end

      private

      def apply_role_set(role_ids)
        ProjectGroups::SetGroupRoleSet.call(group: @group, role_ids: role_ids.uniq)
        flash[:notice] = t("project_groups.admin.flash.saved")
        redirect_to(safe_back_url || edit_group_path(@group, tab: :project_group_roles), status: :see_other)
      end

      def current_role_ids
        @group.project_group_roles.pluck(:role_id)
      end

      def param_role_id
        params[:role_id].to_i
      end

      def find_group
        @group = Group.find(params[:id])
      end

      # Only accept a local relative path, to avoid an open-redirect via back_url.
      def safe_back_url
        url = params[:back_url].to_s
        return if url.blank? || !url.start_with?("/") || url.start_with?("//", '/\\')

        url
      end
    end
  end
end
