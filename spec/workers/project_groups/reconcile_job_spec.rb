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

RSpec.describe ProjectGroups::ReconcileJob do
  shared_let(:project) { create(:project) }
  shared_let(:user)    { create(:user) }
  shared_let(:role)    { create(:project_role) }
  shared_let(:group)   { create(:group).tap { |g| ProjectGroups::GroupRole.create!(group: g, role:) } }

  it "reconciles the given (user, project) pair" do
    assignment = ProjectGroups::Assignment.create!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user:)

    described_class.perform_now(user.id, project.id)

    member = Member.find_by(user_id: user.id, project_id: project.id, entity_type: nil, entity_id: nil)
    expect(member).to be_present
    expect(member.roles).to contain_exactly(role)
  end

  it "is a safe no-op for a missing user or project" do
    expect { described_class.perform_now(-1, -1) }.not_to raise_error
  end
end
