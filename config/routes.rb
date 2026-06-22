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

# Routes for the "Groups and Members" project page.
OpenProject::Application.routes.draw do
  scope "projects/:project_id" do
    # Groups list — the module landing page.
    get    "project_groups",
           to: "project_groups/groups#index",
           as: :project_groups

    post   "project_groups/groups",
           to: "project_groups/groups#create",
           as: :project_groups_attach_group

    delete "project_groups/groups/:id",
           to: "project_groups/groups#destroy",
           as: :project_groups_detach_group

    # Members of a single group within the project.
    get    "project_groups/groups/:assignment_id/members",
           to: "project_groups/memberships#index",
           as: :project_group_members

    post   "project_groups/groups/:assignment_id/members",
           to: "project_groups/memberships#create",
           as: :project_group_add_member

    delete "project_groups/groups/:assignment_id/members/:id",
           to: "project_groups/memberships#destroy",
           as: :project_group_remove_member
  end

  # Global admin: define each group's role-set.
  namespace :project_groups do
    namespace :admin do
      resources :group_roles, only: %i[index edit update]
    end
  end
end
