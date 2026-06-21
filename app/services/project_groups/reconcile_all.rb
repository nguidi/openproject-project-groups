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
  # Full re-sync / drift repair: reconciles every (user, project) pair that either
  # has a project-scoped group membership OR a managed member role. Reconciling the
  # managed-role side too means orphaned roles (membership removed without a
  # reconcile, e.g. a direct DB change) get cleaned up. Returns the pair count.
  class ReconcileAll
    def self.call
      new.call
    end

    def call
      pairs.each { |user, project| Reconcile.call(user:, project:) }
      pairs.size
    end

    private

    def pairs
      @pairs ||= (membership_pairs + managed_pairs)
                 .uniq { |user, project| [user.id, project.id] }
    end

    def membership_pairs
      Membership
        .includes(:user, assignment: :project)
        .filter_map { |m| [m.user, m.project] if m.user && m.project }
    end

    def managed_pairs
      member_ids = MemberRole.where(id: ManagedMemberRole.select(:member_role_id)).select(:member_id)
      Member
        .where(id: member_ids)
        .includes(:principal, :project)
        .filter_map { |m| [m.principal, m.project] if m.principal.is_a?(User) && m.project }
    end
  end
end
