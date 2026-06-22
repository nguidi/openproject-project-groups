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
  module Members
    # Paginated table of the users in one group within a project. Inherits the generic
    # native table template from ::TableComponent; rows rendered by the sibling
    # ProjectGroups::Members::RowComponent.
    class TableComponent < ::TableComponent
      options :project, :assignment

      columns :name, :mail

      def sortable? = false

      def headers
        [
          ["name", { caption: User.human_attribute_name(:name) }],
          ["mail", { caption: User.human_attribute_name(:mail) }]
        ]
      end

      def empty_row_message
        I18n.t("project_groups.no_members")
      end
    end
  end
end
