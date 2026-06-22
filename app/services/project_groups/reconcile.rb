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
  # Materialises the project-scoped group memberships of one (user, project) pair
  # into native Member / MemberRole rows, and removes the ones no longer wanted.
  #
  # Invariants (README §4, §9):
  # * Idempotent — safe to re-run; a no-op when already in sync.
  # * "Direct wins" — only ever adds/removes MemberRoles it owns (tracked in
  #   project_groups_managed_member_roles). A role the user holds from anywhere
  #   else (manual member, native group inheritance) is never duplicated or removed.
  # * Project-scoped — desired roles come only from the user's group memberships
  #   *in this project*.
  #
  # Like core's group inheritance, derived roles are written directly (not via
  # Members::CreateService) to avoid notification side effects; an emptied member
  # is destroyed. After committing a change it emits the matching member event
  # (MEMBER_CREATED / MEMBER_UPDATED / MEMBER_DESTROYED, send_notifications: false) so
  # event-driven integrations react exactly as they do for native group-inherited
  # members — notably the storages module's automatically-managed Nextcloud folder
  # permission sync (it debounces on those events; the e-mail mailer is suppressed by
  # send_notifications: false). Mirrors Notifications::GroupMemberAlteredJob.
  class Reconcile
    def self.call(user:, project:)
      new(user:, project:).call
    end

    # The distinct (user, project) pairs a group touches.
    def self.pairs_for_group(group)
      Membership
        .joins(:assignment)
        .where(project_groups_assignments: { group_id: group.id })
        .includes(:user, assignment: :project)
        .map { |m| [m.user, m.project] }
        .uniq { |user, project| [user.id, project.id] }
    end

    # Reconcile every (user, project) touched by a group, synchronously. For the
    # role-set-edit fan-out the admin path enqueues ReconcileJob instead (async).
    def self.for_group(group)
      pairs_for_group(group).each { |user, project| call(user:, project:) }
    end

    def initialize(user:, project:)
      @user = user
      @project = project
    end

    def call
      outcome = nil
      ApplicationRecord.transaction { outcome = reconcile }
      # Publish AFTER commit so subscribers (storage sync, etc.) never act on a
      # rolled-back change. send_notifications: false → no add/remove e-mails (README §9).
      publish_member_event(outcome) if outcome
      outcome
    end

    private

    attr_reader :user, :project

    # Returns nil when already in sync (no event), else { member:, event: } describing
    # what changed so #call can publish the matching member event after commit.
    def reconcile
      desired = desired_role_ids
      member = find_member
      existed = member.present?
      managed = managed_member_roles(member)

      present_role_ids = member ? member.member_roles.map(&:role_id) : []
      to_add = desired - present_role_ids                            # absent & wanted
      to_remove = managed.reject { |mr| desired.include?(mr.role_id) } # ours & no longer wanted
      return nil if to_add.empty? && to_remove.empty?                # already in sync

      member = add_roles(member, to_add) if to_add.any?
      remove_member_roles(to_remove) if to_remove.any?
      destroyed = destroy_member_if_empty(member)

      { member:, event: member_event(existed:, destroyed:) }
    end

    def member_event(existed:, destroyed:)
      return OpenProject::Events::MEMBER_DESTROYED if destroyed

      existed ? OpenProject::Events::MEMBER_UPDATED : OpenProject::Events::MEMBER_CREATED
    end

    def publish_member_event(outcome)
      OpenProject::Notifications.send(outcome[:event],
                                      member: outcome[:member],
                                      send_notifications: false)
    end

    # Project roles granted by every group the user belongs to *in this project*.
    def desired_role_ids
      group_ids = user_group_ids
      return [] if group_ids.empty?

      role_ids = GroupRole.where(group_id: group_ids).distinct.pluck(:role_id)
      # Only roles valid for a project member (excludes global / work-package roles).
      Role.where(id: role_ids).select(&:member?).map(&:id)
    end

    def user_group_ids
      Assignment
        .where(project_id: project.id)
        .where(id: Membership.where(user_id: user.id).select(:assignment_id))
        .pluck(:group_id)
    end

    def find_member
      Member.find_by(user_id: user.id, project_id: project.id, entity_type: nil, entity_id: nil)
    end

    # The MemberRoles on this member that we own.
    def managed_member_roles(member)
      return [] unless member

      member.member_roles.where(id: ManagedMemberRole.select(:member_role_id)).to_a
    end

    def add_roles(member, role_ids)
      member ||= Member.new(principal: user, project:)
      created = role_ids.map { |role_id| member.member_roles.build(role_id:) }
      member.save!
      created.each { |mr| ManagedMemberRole.create!(member_role: mr) }
      member
    end

    def remove_member_roles(member_roles)
      # Destroying the MemberRole cascades its managed_member_roles row (FK).
      member_roles.each(&:destroy!)
    end

    # Returns true if the member was destroyed (no managed/other roles left).
    def destroy_member_if_empty(member)
      return false unless member
      return false if member.member_roles.reload.any?

      member.destroy!
      true
    end
  end
end
