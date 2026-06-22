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
  # The "Groups and Members" project page: attach/detach global groups to this
  # project and add/remove users in them. Every mutation reconciles the affected
  # user(s) into native project members (ProjectGroups::Reconcile).
  class MembershipsController < ApplicationController
    before_action :find_project_by_project_id
    before_action :authorize

    menu_item :project_groups

    def index
      @assignments = Assignment
                     .where(project: @project)
                     .includes(:group, { group: :project_group_roles }, memberships: :user)
                     .to_a
      attached_group_ids = @assignments.map(&:group_id)
      @attachable_groups = Group.where.not(id: attached_group_ids).order(:lastname)
      @conflicting_groups = conflicting_native_group_members
    end

    def attach_group
      group = Group.find(params[:group_id])
      Assignment.find_or_create_by!(group:, project: @project)
      flash[:notice] = t("project_groups.flash.group_attached")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    def detach_group
      assignment = project_assignments.find(params[:assignment_id])
      users = assignment.memberships.map(&:user)
      assignment.destroy! # cascades the memberships
      reconcile(users)
      flash[:notice] = t("project_groups.flash.group_detached")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    def create # add a member to a group
      assignment = project_assignments.find(params[:assignment_id])
      user = User.find(params[:user_id])
      Membership.find_or_create_by!(assignment:, user:)
      reconcile([user])
      flash[:notice] = t("project_groups.flash.member_added")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    def destroy # remove a member from a group
      membership = Membership
                   .joins(:assignment)
                   .where(project_groups_assignments: { project_id: @project.id })
                   .find(params[:id])
      user = membership.user
      membership.destroy!
      reconcile([user])
      flash[:notice] = t("project_groups.flash.member_removed")
      redirect_to project_groups_path(project_id: @project), status: :see_other
    end

    private

    def project_assignments
      Assignment.where(project: @project)
    end

    # Groups attached here that are ALSO native members of the project (someone added
    # them via Administration ▸ Groups ▸ Projects) — core then propagates their members
    # independently of us. Surfaced as a warning (README §9 operator caveat). Conflict
    # detection is defined once, as Assignment.conflicting_with_native_membership.
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
