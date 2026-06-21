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

require "spec_helper"

RSpec.describe ProjectGroups::SetGroupRoleSet do
  include ActiveJob::TestHelper

  shared_let(:project) { create(:project) }
  shared_let(:user)    { create(:user) }
  shared_let(:role_a)  { create(:project_role) }
  shared_let(:role_b)  { create(:project_role) }
  shared_let(:group)   { create(:group) }

  before do
    # The user is in the group within the project; role_a already materialised.
    assignment = ProjectGroups::Assignment.create!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user:)
    ProjectGroups::GroupRole.create!(group:, role: role_a)
    ProjectGroups::Reconcile.call(user:, project:)
  end

  def role_ids_for(usr, prj)
    Member.find_by(user_id: usr.id, project_id: prj.id, entity_type: nil, entity_id: nil)
          &.member_roles&.map(&:role_id) || []
  end

  it "applies the role-set immediately and reconciles members via background jobs" do
    perform_enqueued_jobs { described_class.call(group:, role_ids: [role_a.id, role_b.id]) }
    expect(group.project_group_roles.pluck(:role_id)).to contain_exactly(role_a.id, role_b.id)
    expect(role_ids_for(user, project)).to contain_exactly(role_a.id, role_b.id)

    perform_enqueued_jobs { described_class.call(group:, role_ids: [role_b.id]) } # swap a -> b
    expect(role_ids_for(user, project)).to contain_exactly(role_b.id)

    perform_enqueued_jobs { described_class.call(group:, role_ids: []) } # clear
    expect(group.project_group_roles).to be_empty
    expect(Member.find_by(user_id: user.id, project_id: project.id)).to be_nil
  end

  it "enqueues a reconcile job per affected (user, project) pair" do
    expect { described_class.call(group:, role_ids: [role_b.id]) }
      .to have_enqueued_job(ProjectGroups::ReconcileJob).with(user.id, project.id)
  end
end
