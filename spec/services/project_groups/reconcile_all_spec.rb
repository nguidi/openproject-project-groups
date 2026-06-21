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

RSpec.describe ProjectGroups::ReconcileAll do
  shared_let(:project) { create(:project) }
  shared_let(:user)    { create(:user) }
  shared_let(:role)    { create(:project_role) }
  shared_let(:group)   { create(:group).tap { |g| ProjectGroups::GroupRole.create!(group: g, role:) } }

  def member_for(usr)
    Member.find_by(user_id: usr.id, project_id: project.id, entity_type: nil, entity_id: nil)
  end

  it "materialises members that were never reconciled" do
    assignment = ProjectGroups::Assignment.create!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user:) # no reconcile yet
    expect(member_for(user)).to be_nil

    expect(described_class.call).to eq(1)
    expect(member_for(user)).to be_present
    expect(member_for(user).roles).to contain_exactly(role)
  end

  it "cleans up managed roles orphaned by drift (membership removed without reconcile)" do
    assignment = ProjectGroups::Assignment.create!(group:, project:)
    ProjectGroups::Membership.create!(assignment:, user:)
    ProjectGroups::Reconcile.call(user:, project:)
    expect(member_for(user)).to be_present

    # Drift: membership deleted directly, bypassing reconcile
    ProjectGroups::Membership.where(user_id: user.id).delete_all

    described_class.call
    expect(member_for(user)).to be_nil
    expect(ProjectGroups::ManagedMemberRole.count).to eq(0)
  end
end
