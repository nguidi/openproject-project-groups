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

require "open_project/plugins"

module OpenProject
  module ProjectGroups
    # OpenProject plugin engine. Registers the "Groups and Members" project module,
    # its permissions, and patches the core Group model.
    #
    # NOTE: APIs marked "verify against v17" are the version-sensitive bits — boot
    # the dev stack (see DEVELOPMENT.md) and adjust if the DSL differs.
    class Engine < ::Rails::Engine
      engine_name :openproject_project_groups

      include OpenProject::Plugins::ActsAsOpEngine

      register "openproject-project_groups",
               author_url: "https://github.com/nguidi/openproject-project-groups",
               name: "OpenProject Project Groups",
               bundled: false do
        # "Groups and Members" is a per-project module so it can be toggled in
        # Project Settings ▸ Modules (README §2 "per-project opt-in"). Enabling it
        # is what turns our flow on for a project (and, in Phase 2, hides the
        # native Members page).
        project_module :project_groups do
          permission :view_project_groups,
                     { "project_groups/groups" => %i[index],
                       "project_groups/memberships" => %i[index] },
                     permissible_on: :project

          permission :manage_project_group_members,
                     { "project_groups/groups" => %i[index create destroy],
                       "project_groups/memberships" => %i[index create destroy] },
                     permissible_on: :project
        end

        # TODO (Phase 3): global permission `manage_project_group_roles`
        # (permissible_on: :global) for the admin role-set screen. Admin-only for now.

        # "Groups and Members" project menu entry — shown only where the module is
        # enabled (the per-project toggle, README §2), right after native Members.
        # Registered inside `register` (deferred) so `Redmine` is loaded by then;
        # calling Redmine::MenuManager at class-load time fails for an external plugin.
        menu :project_menu,
             :project_groups,
             { controller: "/project_groups/groups", action: "index" },
             caption: :project_module_project_groups,
             param: :project_id,
             after: :members,
             icon: "people",
             if: ->(project) { project.module_enabled?(:project_groups) }
      end

      # Adds project_group_roles / project_group_assignments associations to Group.
      # Looks up OpenProject::ProjectGroups::Patches::GroupPatch.
      patches %i[Group]

      # Per-project toggle (README §2): hide the native "Members" project menu item
      # on projects where our module is enabled, so there's a single way in. Uses the
      # MenuManager's add_condition (ANDed with any existing condition) rather than
      # deleting the item (which would orphan its :members_menu child).
      #
      # Queued via an initializer running AFTER config/initializers, so core's
      # :members item is already registered when our builder block runs.
      initializer "openproject_project_groups.menus",
                  after: :load_config_initializers do
        # Hide native Members where our module is enabled (per-project toggle).
        ::Redmine::MenuManager.map(:project_menu) do |menu|
          menu.add_condition(
            :members,
            ->(project) { project.blank? || !project.module_enabled?(:project_groups) }
          )
        end

        # Admin entry for the group role-set screen (Phase 3), under Users & Permissions.
        ::Redmine::MenuManager.map(:admin_menu) do |menu|
          menu.push :project_group_roles,
                    { controller: "/project_groups/admin/group_roles", action: :index },
                    parent: :users_and_permissions,
                    caption: :label_project_group_roles,
                    if: ->(*) { User.current.admin? }
        end
      end
    end
  end
end
