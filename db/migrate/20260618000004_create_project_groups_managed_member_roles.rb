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

class CreateProjectGroupsManagedMemberRoles < ActiveRecord::Migration[7.1]
  def change
    create_table :project_groups_managed_member_roles do |t|
      # Marks a native MemberRole as plugin-managed (created by reconciliation).
      # Keyed by member_role only — a managed role may be wanted by several
      # memberships at once, so it must not be tied to a single one. Provenance
      # ("which group granted it") is derived, not stored. Cascades away if core
      # deletes the MemberRole (e.g. member/user removal).
      t.references :member_role, null: false,
                   index: { unique: true, name: "index_pg_managed_member_roles_on_member_role" },
                   foreign_key: { to_table: :member_roles, on_delete: :cascade }

      t.timestamps
    end
  end
end
