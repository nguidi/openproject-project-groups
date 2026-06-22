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
  # The members of ONE group within the project: a paginated list (Name, Email, remove
  # action) scoped to an assignment, plus add. Each mutation reconciles the affected
  # user into native project members (ProjectGroups::Reconcile).
  class MembershipsController < ApplicationController
    before_action :find_project_by_project_id
    before_action :authorize
    before_action :find_assignment

    menu_item :project_groups

    def index
      @members = @assignment.memberships
                            .includes(:user)
                            .order(:id)
                            .paginate(page: params[:page], per_page: per_page)
    end

    def create # add a member to the group
      user = User.find(params[:user_id])
      Membership.find_or_create_by!(assignment: @assignment, user:)
      Reconcile.call(user:, project: @project)
      flash[:notice] = t("project_groups.flash.member_added")
      redirect_to members_path, status: :see_other
    end

    def destroy # remove a member from the group
      membership = @assignment.memberships.find(params[:id])
      user = membership.user
      membership.destroy!
      Reconcile.call(user:, project: @project)
      flash[:notice] = t("project_groups.flash.member_removed")
      redirect_to members_path, status: :see_other
    end

    private

    def find_assignment
      @assignment = Assignment.where(project: @project).find(params[:assignment_id])
    end

    def members_path
      project_group_members_path(project_id: @project, assignment_id: @assignment)
    end

    def per_page
      params[:per_page].presence || 25
    end
  end
end
