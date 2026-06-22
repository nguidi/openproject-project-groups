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
  module Groups
    # One row of the groups table. The model is a ProjectGroups::Assignment. Column
    # methods (name, roles) and button_links are consumed by the generic
    # ::RowComponent template. The detach button opens a confirmation dialog rendered
    # by the view (keyed by "pg-detach-<assignment id>").
    class RowComponent < ::RowComponent
      def assignment = model
      def group = assignment.group
      def project = table.project

      def name
        render(Primer::Beta::Link.new(
                 href: helpers.project_group_members_path(project_id: project, assignment_id: assignment.id)
               )) { group.name }
      end

      def roles
        list = group.project_group_role_set.to_a.sort_by(&:name)
        if list.empty?
          render(Primer::Beta::Label.new(scheme: :attention)) { I18n.t("project_groups.no_roles_short") }
        else
          safe_join(list.map { |role| render(Primer::Beta::Label.new(scheme: :secondary, mr: 1)) { role.name } })
        end
      end

      def button_links
        [detach_button]
      end

      def detach_button
        render(Primer::Beta::IconButton.new(
                 icon: :trash,
                 scheme: :danger,
                 size: :small,
                 "aria-label": I18n.t("project_groups.button_detach"),
                 data: { show_dialog_id: "pg-detach-#{assignment.id}" }
               ))
      end
    end
  end
end
