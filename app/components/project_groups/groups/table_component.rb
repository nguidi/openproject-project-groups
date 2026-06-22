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
    # Paginated table of the groups attached to a project. Inherits the generic
    # native table template/markup from ::TableComponent; rows are rendered by the
    # sibling ::RowComponent (ProjectGroups::Groups::RowComponent). Not sortable —
    # the controller paginates the collection in a stable order.
    class TableComponent < ::TableComponent
      options :project

      columns :name, :roles

      def sortable? = false

      def headers
        [
          ["name", { caption: I18n.t("project_groups.column_group") }],
          ["roles", { caption: I18n.t("project_groups.label_roles") }]
        ]
      end

      def empty_row_message
        I18n.t("project_groups.no_groups")
      end
    end
  end
end
