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
    # One row of the members table. The model is a ProjectGroups::Membership. The
    # remove button opens a confirmation dialog rendered by the view (keyed by
    # "pg-remove-<membership id>").
    class RowComponent < ::RowComponent
      def membership = model
      def user = membership.user

      def name = user.name
      def mail = user.mail

      def button_links
        [remove_button]
      end

      def remove_button
        render(Primer::Beta::IconButton.new(
                 icon: :trash,
                 scheme: :danger,
                 size: :small,
                 "aria-label": I18n.t("project_groups.button_remove"),
                 data: { show_dialog_id: "pg-remove-#{membership.id}" }
               ))
      end
    end
  end
end
