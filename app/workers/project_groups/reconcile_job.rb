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
  # Async wrapper around Reconcile for one (user, project) pair. Used for fan-out
  # (a group's role-set change touching many projects). Looks the records up by id
  # so a deleted user/project is a safe no-op.
  class ReconcileJob < ApplicationJob
    def perform(user_id, project_id)
      user = User.find_by(id: user_id)
      project = Project.find_by(id: project_id)
      return unless user && project

      Reconcile.call(user:, project:)
    end
  end
end
