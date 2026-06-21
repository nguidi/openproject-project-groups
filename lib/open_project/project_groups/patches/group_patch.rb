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

module OpenProject
  module ProjectGroups
    module Patches
      # Adds the role-set and assignment associations to the core Group model.
      # Included into Group via `patches %i[Group]` in the engine.
      module GroupPatch
        def self.included(base)
          base.class_eval do
            # The group's role-set (the project roles this group represents).
            has_many :project_group_roles,
                     class_name: "ProjectGroups::GroupRole",
                     foreign_key: :group_id,
                     dependent: :destroy

            # Roles, through the role-set join.
            has_many :project_group_role_set,
                     class_name: "Role",
                     through: :project_group_roles,
                     source: :role

            # Projects this group is attached to (our project-scoped assignments).
            has_many :project_group_assignments,
                     class_name: "ProjectGroups::Assignment",
                     foreign_key: :group_id,
                     dependent: :destroy
          end
        end
      end
    end
  end
end
