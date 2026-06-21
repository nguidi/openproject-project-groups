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

RSpec.describe ProjectGroups::ManagedMemberRole do
  shared_let(:role)   { create(:project_role) }
  shared_let(:member) { create(:member, principal: create(:user), project: create(:project), roles: [role]) }

  let(:member_role) { member.member_roles.first }

  it "maps to the prefixed table" do
    expect(described_class.table_name).to eq("project_groups_managed_member_roles")
  end

  it "marks a member_role as plugin-managed" do
    expect(described_class.new(member_role:)).to be_valid
  end

  it "records each member_role at most once" do
    described_class.create!(member_role:)
    expect(described_class.new(member_role:)).not_to be_valid
  end

  it "is removed when its member_role is destroyed (FK cascade)" do
    described_class.create!(member_role:)

    expect { member_role.destroy! }.to change(described_class, :count).by(-1)
  end
end
