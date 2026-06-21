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

# The associations the engine adds to the core Group via `patches %i[Group]`.
RSpec.describe OpenProject::ProjectGroups::Patches::GroupPatch do
  shared_let(:group)   { create(:group) }
  shared_let(:role)    { create(:project_role) }
  shared_let(:project) { create(:project) }

  it "exposes the group's role-set through the patched associations" do
    ProjectGroups::GroupRole.create!(group:, role:)

    expect(group.project_group_roles.map(&:role_id)).to contain_exactly(role.id)
    expect(group.project_group_role_set).to contain_exactly(role)
  end

  it "lists the project-scoped assignments of the group" do
    assignment = ProjectGroups::Assignment.create!(group:, project:)

    expect(group.project_group_assignments).to contain_exactly(assignment)
  end

  it "destroys the role-set and assignments together with the group (dependent: :destroy)" do
    expect(Group.reflect_on_association(:project_group_roles).options[:dependent]).to eq(:destroy)
    expect(Group.reflect_on_association(:project_group_assignments).options[:dependent]).to eq(:destroy)
  end
end
