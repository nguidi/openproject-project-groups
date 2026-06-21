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

RSpec.describe ProjectGroups::Assignment do
  shared_let(:group)   { create(:group) }
  shared_let(:project) { create(:project) }

  it "maps to the prefixed table" do
    expect(described_class.table_name).to eq("project_groups_assignments")
  end

  it "forbids the same group attached twice to one project" do
    described_class.create!(group:, project:)
    expect(described_class.new(group:, project:)).not_to be_valid
  end

  it "allows the same group in a different project" do
    described_class.create!(group:, project:)
    expect(described_class.new(group:, project: create(:project))).to be_valid
  end

  it "destroys its memberships when detached (dependent: :destroy)" do
    assignment = described_class.create!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user: create(:user))

    expect { assignment.destroy! }.to change(ProjectGroups::Membership, :count).by(-1)
  end

  describe "#roles" do
    it "returns the group's role-set" do
      role = create(:project_role)
      ProjectGroups::GroupRole.create!(group:, role:)
      assignment = described_class.create!(group:, project:)

      expect(assignment.roles).to contain_exactly(role)
    end

    it "is empty when the group has no role-set" do
      assignment = described_class.create!(group:, project:)
      expect(assignment.roles).to be_empty
    end
  end

  describe ".conflicting_with_native_membership" do
    shared_let(:role) { create(:project_role) }

    it "flags an assignment whose group is also a native member of the project" do
      assignment = described_class.create!(group:, project:)
      create(:member, principal: group, project:, roles: [role]) # core propagation

      expect(described_class.conflicting_with_native_membership).to include(assignment)
    end

    it "ignores an assignment with no native group membership" do
      described_class.create!(group:, project:)

      expect(described_class.conflicting_with_native_membership).to be_empty
    end

    it "does not flag a native group membership in a different project" do
      assignment = described_class.create!(group:, project:)
      create(:member, principal: group, project: create(:project), roles: [role])

      expect(described_class.conflicting_with_native_membership).not_to include(assignment)
    end

    it "does not flag an individual user's native membership (only the group's)" do
      assignment = described_class.create!(group:, project:)
      create(:member, principal: create(:user), project:, roles: [role])

      expect(described_class.conflicting_with_native_membership).not_to include(assignment)
    end
  end
end
