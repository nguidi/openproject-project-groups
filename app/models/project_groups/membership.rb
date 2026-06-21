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
  # A user placed into a group within a project — the project-scoped membership the
  # plugin exists to provide. Kept here, NOT in native GroupUser, which is global.
  #
  # Reconciliation (Phase 1) turns this into native Member/MemberRole rows for the
  # user in the assignment's project, tracked via managed_member_roles.
  class Membership < ApplicationRecord
    belongs_to :assignment, class_name: "ProjectGroups::Assignment"
    belongs_to :user, class_name: "User"

    validates :user_id, uniqueness: { scope: :assignment_id }

    delegate :group, :project, to: :assignment
  end
end
