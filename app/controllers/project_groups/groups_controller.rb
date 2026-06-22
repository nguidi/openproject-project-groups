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
  # "Groups and Members" landing page: a paginated list of the groups attached to this
  # project (Name, Roles, detach action), plus attach. Drilling into a group's name
  # opens its members page (MembershipsController). Modeled on the native Members module.
  class GroupsController < ApplicationController
    before_action :find_project_by_project_id
    before_action :authorize

    menu_item :project_groups

    def index
      @groups = Assignment
                .where(project: @project)
                .includes(group: :project_group_roles)
                .order(:id)
                .paginate(page: params[:page], per_page: per_page)
      @conflicting_groups = conflicting_native_group_members
    end

    def create # attach a group to the project
      group = Group.find(params[:group_id])
      Assignment.find_or_create_by!(group:, project: @project)
      flash[:notice] = t("project_groups.flash.group_attached")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    def destroy # detach a group from the project
      assignment = project_assignments.find(params[:id])
      users = assignment.memberships.map(&:user)
      assignment.destroy! # cascades the memberships
      reconcile(users)
      flash[:notice] = t("project_groups.flash.group_detached")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    private

    def project_assignments
      Assignment.where(project: @project)
    end

    def per_page
      params[:per_page].presence || 25
    end

    # Groups attached here that are ALSO native members of the project (README §9).
    def conflicting_native_group_members
      Assignment.where(project: @project)
                .conflicting_with_native_membership
                .includes(:group)
                .map(&:group)
    end

    def reconcile(users)
      users.uniq.each { |user| Reconcile.call(user:, project: @project) }
    end
  end
end
