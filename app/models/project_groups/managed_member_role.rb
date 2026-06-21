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
  # Marks a native MemberRole as plugin-managed (created by reconciliation).
  # Reconciliation only ever removes roles recorded here, so it never clobbers a
  # user's manually-assigned roles ("direct wins" — README §9.1). Keyed by the
  # MemberRole only: a role granted by several groups at once is a single managed
  # record, so it survives until *no* group still wants it.
  class ManagedMemberRole < ApplicationRecord
    belongs_to :member_role

    validates :member_role_id, uniqueness: true
  end
end
