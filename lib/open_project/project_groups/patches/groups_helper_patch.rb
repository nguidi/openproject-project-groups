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
      # Adds a "Project roles" tab (the group's role-set) to the native Group edit page
      # (Administration ▸ Groups ▸ <group>), the same way the LDAP module adds
      # "Synchronized groups": by extending GroupsHelper#group_settings_tabs. The tab
      # renders the `groups/project_group_roles` partial shipped by this plugin.
      #
      # Prepended onto ::GroupsHelper from the engine (config.to_prepare).
      module GroupsHelperPatch
        def group_settings_tabs(group)
          tabs = super
          our_tab = {
            name: "project_group_roles",
            partial: "groups/project_group_roles",
            path: edit_group_path(group, tab: :project_group_roles),
            label: :"project_groups.group_tab"
          }

          # Place it right after "Global roles" so the role tabs sit together.
          index = tabs.index { |tab| tab[:name] == "global_roles" }
          index ? tabs.insert(index + 1, our_tab) : tabs << our_tab
          tabs
        end
      end
    end
  end
end
