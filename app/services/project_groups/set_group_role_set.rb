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
  # Sets a group's role-set to exactly the given role ids, then propagates the
  # change to every (user, project) the group touches (README §9.2 "role-set edit,
  # immediate"). The role-set change is applied synchronously (the admin sees it at
  # once); the member reconciliation is fanned out to background jobs so a group used
  # across many projects doesn't block the request. Used by the admin role-set screen.
  class SetGroupRoleSet
    def self.call(group:, role_ids:)
      new(group:, role_ids:).call
    end

    def initialize(group:, role_ids:)
      @group = group
      @role_ids = Array(role_ids).map(&:to_i).uniq
    end

    def call
      ApplicationRecord.transaction do
        current = GroupRole.where(group_id: @group.id).pluck(:role_id)
        GroupRole.where(group_id: @group.id, role_id: current - @role_ids).destroy_all
        (@role_ids - current).each { |role_id| GroupRole.create!(group_id: @group.id, role_id:) }
      end

      Reconcile.pairs_for_group(@group).each do |user, project|
        ReconcileJob.perform_later(user.id, project.id)
      end
    end
  end
end
