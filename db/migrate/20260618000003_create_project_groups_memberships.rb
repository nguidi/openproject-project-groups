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

class CreateProjectGroupsMemberships < ActiveRecord::Migration[7.1]
  def change
    create_table :project_groups_memberships do |t|
      t.references :assignment, null: false, index: true,
                   foreign_key: { to_table: :project_groups_assignments, on_delete: :cascade }
      # User is a Principal — stored in the `users` table (STI).
      t.references :user, null: false, index: true,
                   foreign_key: { to_table: :users, on_delete: :cascade }

      t.timestamps
    end

    add_index :project_groups_memberships, %i[assignment_id user_id],
              unique: true, name: "index_pg_memberships_on_assignment_and_user"
  end
end
