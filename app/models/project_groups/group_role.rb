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
  # One role in a (native) group's role-set. Global per group — used in every
  # project the group is attached to. Only assignable PROJECT roles belong here
  # (Non member / Anonymous / global roles are excluded — enforced in Phase 3 UI).
  class GroupRole < ApplicationRecord
    belongs_to :group, class_name: "Group"
    belongs_to :role

    validates :role_id, uniqueness: { scope: :group_id }
  end
end
