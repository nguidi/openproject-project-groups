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

namespace :project_groups do
  desc "Reconcile all project-scoped group memberships into native members (drift repair)"
  task reconcile_all: :environment do
    count = ProjectGroups::ReconcileAll.call
    puts "[project_groups] Reconciled #{count} (user, project) pair(s)."
  end

  desc "Report native group/project membership conflicts (groups added to a project via core, firing propagation)"
  task check: :environment do
    conflicts = ProjectGroups::Assignment
                .conflicting_with_native_membership
                .includes(:group, :project)

    if conflicts.empty?
      puts "[project_groups] OK — no native group/project membership conflicts."
    else
      puts "[project_groups] #{conflicts.size} conflict(s): a group attached here is ALSO a native member of the project (core propagation active):"
      conflicts.each do |assignment|
        puts "  - group '#{assignment.group.name}' in project '#{assignment.project.name}' " \
             "(identifier: #{assignment.project.identifier})"
      end
      puts "Remove these from the group's Projects tab in Administration ▸ Groups to avoid duplicate/conflicting roles."
    end
  end
end
