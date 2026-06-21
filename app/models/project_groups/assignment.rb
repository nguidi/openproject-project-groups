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
  # A (native) group made available in a specific project. "This group is active in
  # this project." Memberships hang off an assignment, so they carry group+project.
  class Assignment < ApplicationRecord
    belongs_to :group, class_name: "Group"
    belongs_to :project

    has_many :memberships,
             class_name: "ProjectGroups::Membership",
             dependent: :destroy

    validates :project_id, uniqueness: { scope: :group_id }

    # Assignments whose group is ALSO a native member of the assignment's project
    # (someone added it via Administration ▸ Groups ▸ Projects), so core propagates
    # its members independently of this plugin — the operator caveat in README §9.
    # The plugin's "what counts as a conflict" definition lives here only. A group
    # acts as a Member principal, so its principal id is the member's user_id; a
    # native group/project membership carries entity_id: nil.
    scope :conflicting_with_native_membership, -> {
      where(
        Member.where(entity_id: nil)
              .where("members.user_id = project_groups_assignments.group_id")
              .where("members.project_id = project_groups_assignments.project_id")
              .arel.exists
      )
    }

    # The project roles this assignment grants (the group's role-set).
    def roles
      Role.where(id: GroupRole.where(group_id:).select(:role_id))
    end
  end
end
